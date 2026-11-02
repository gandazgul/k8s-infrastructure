#!/usr/bin/env python3
"""Guarded, one-time valuesFrom migration; defaults to server dry-run.

Credentials are read only into process memory. Never print resource bodies,
kubectl stderr, inline values, Secret bytes, or legacy apply annotations.
"""

import argparse
import base64
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys

import yaml


NAMES = ("bitwarden", "forecastle", "mosquitto", "plex", "sftpgo")
FILES = ("Bitwarden.yaml", "Forecastle.yaml", "Mosquitto.yaml", "Plex.yaml", "SFTPGo.yaml")
LEGACY = "kubectl.kubernetes.io/last-applied-configuration"


class GuardError(Exception):
    """Safe-to-print error whose message must never include resource content."""


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True, allow_nan=False)


def value_hash(value):
    return hashlib.sha256(canonical(value).encode()).hexdigest()


def run_json(kubectl, args, payload=None):
    result = subprocess.run(
        [kubectl, "--request-timeout=30s", *args],
        input=None if payload is None else json.dumps(payload),
        text=True, capture_output=True, check=False,
    )
    if result.returncode:
        raise GuardError("kubectl request failed; response suppressed to protect credentials")
    try:
        return json.loads(result.stdout)
    except (ValueError, TypeError):
        raise GuardError("kubectl returned an invalid JSON response") from None


def get(kubectl, kind, name):
    return run_json(kubectl, ["-n", "default", "get", kind, name, "-o", "json"])


def check_ready(resource, condition):
    status = resource.get("status", {})
    if status.get("observedGeneration") != resource["metadata"].get("generation"):
        raise GuardError("prerequisite has not observed its current generation")
    if not any(c.get("type") == condition and c.get("status") == "True"
               for c in status.get("conditions", [])):
        raise GuardError("prerequisite is not currently Ready/Synced")


def make_plan(live, desired, secret, baseline):
    name = desired["metadata"]["name"]
    if name not in NAMES or live["metadata"].get("uid") != baseline["uid"]:
        raise GuardError("HelmRelease identity changed")
    if live["metadata"].get("namespace") != "default":
        raise GuardError("HelmRelease namespace changed")
    want = copy.deepcopy(desired["spec"])
    current = copy.deepcopy(live["spec"])
    if "values" in want:
        raise GuardError("desired source must not contain inline values")
    refs = want.pop("valuesFrom", [])
    last = {"kind": "Secret", "name": name + "-gitops-values", "valuesKey": "values.yaml", "optional": False}
    if not refs or canonical(refs[-1]) != canonical(last):
        raise GuardError("desired final values reference is not the required dedicated Secret")
    if any(ref.get("targetPath") for ref in refs[:-1]):
        raise GuardError("targetPath reference requires a separate precedence review")
    old_refs = current.pop("valuesFrom", [])
    has_values = "values" in current
    inline = current.pop("values", None)
    if canonical(want) != canonical(current):
        raise GuardError("non-values HelmRelease spec drift detected")
    if name == "sftpgo" and current.get("suspend") is not True:
        raise GuardError("SFTPGo must remain suspended")
    digest = live.get("status", {}).get("lastAttemptedConfigDigest")
    if digest != baseline["controllerConfigDigest"]:
        raise GuardError("controller configuration digest changed since capture")
    try:
        sealed_values = json.loads(base64.b64decode(secret["data"]["values.yaml"], validate=True))
    except (KeyError, ValueError, TypeError):
        raise GuardError("dedicated Secret values.yaml must contain the captured JSON object") from None
    if not isinstance(sealed_values, dict):
        raise GuardError("dedicated Secret values must be a JSON object")
    if value_hash(sealed_values) != baseline["inlineValuesSha256"]:
        raise GuardError("dedicated Secret differs from captured inline values")
    already = not has_values and canonical(old_refs) == canonical(refs)
    if not already:
        if not has_values or not isinstance(inline, dict):
            raise GuardError("unexpected partial adoption state")
        if canonical(old_refs) != canonical(refs[:-1]):
            raise GuardError("existing valuesFrom is not the exact desired prefix")
        if canonical(inline) != canonical(sealed_values):
            raise GuardError("live inline values do not equal decrypted dedicated Secret")
    # No credential values are included in the JSONPatch, even in test operations.
    patch = [
        {"op": "test", "path": "/metadata/uid", "value": live["metadata"]["uid"]},
        {"op": "test", "path": "/metadata/resourceVersion", "value": live["metadata"]["resourceVersion"]},
    ]
    if not already:
        patch.extend([
            {"op": "add", "path": "/spec/valuesFrom", "value": refs},
            {"op": "remove", "path": "/spec/values"},
        ])
    if LEGACY in live["metadata"].get("annotations", {}):
        patch.append({"op": "remove", "path": "/metadata/annotations/kubectl.kubernetes.io~1last-applied-configuration"})
    return {"name": name, "patch": patch, "already": already,
            "uid": live["metadata"]["uid"], "refs": refs,
            "inlineValuesSha256": value_hash(sealed_values), "controllerConfigDigest": digest}


def validate_response(response, plan):
    if response["metadata"].get("uid") != plan["uid"]:
        raise GuardError("patch response changed HelmRelease identity")
    if "values" in response["spec"] or canonical(response["spec"].get("valuesFrom", [])) != canonical(plan["refs"]):
        raise GuardError("patch did not establish the exact desired values source")
    if LEGACY in response["metadata"].get("annotations", {}):
        raise GuardError("legacy apply annotation was not removed")


def validate_prefix_ref(ref, existing):
    if (set(ref) - {"kind", "name", "optional", "valuesKey"}
            or ref.get("kind") != "Secret"
            or ref.get("name") not in existing
            or ref.get("optional", False) is not False):
        raise GuardError("prefix values reference requires a separate source review")


def check_existing_secret(kubectl, name, expected):
    current = get(kubectl, "secret", name)
    if current["metadata"]["uid"] != expected["uid"] or value_hash(current.get("data", {})) != expected["dataSha256"]:
        raise GuardError("existing Secret identity or bytes changed during adoption")


def self_test():
    # Synthetic data only: test atomicity/drift gates without Kubernetes or credentials.
    name = "bitwarden"
    values = {"env": {"BOOL_STRING": "false"}, "nested": {"n": 2}, "list": [1, True]}
    ref = {"kind": "Secret", "name": name + "-gitops-values", "valuesKey": "values.yaml", "optional": False}
    live = {"metadata": {"name": name, "namespace": "default", "uid": "unit-uid", "resourceVersion": "7", "annotations": {LEGACY: "synthetic"}},
            "spec": {"chart": {"spec": {"version": "1"}}, "values": values, "valuesFrom": []},
            "status": {"lastAttemptedConfigDigest": "unit-controller-digest"}}
    desired = {"metadata": {"name": name}, "spec": {"chart": {"spec": {"version": "1"}}, "valuesFrom": [ref]}}
    secret = {"data": {"values.yaml": base64.b64encode(canonical(values).encode()).decode()}}
    baseline = {"uid": "unit-uid", "inlineValuesSha256": value_hash(values), "controllerConfigDigest": "unit-controller-digest"}
    plan = make_plan(live, desired, secret, baseline)
    assert [p["op"] for p in plan["patch"]] == ["test", "test", "add", "remove", "remove"]
    assert "BOOL_STRING" not in canonical(plan["patch"])
    count = 2
    for mutate in [lambda x: x["metadata"].update(uid="other"),
                   lambda x: x["spec"]["chart"]["spec"].update(version="2"),
                   lambda x: x["spec"].update(valuesFrom=[{"kind": "Secret", "name": "unexpected"}]),
                   lambda x: x["spec"]["values"]["env"].update(BOOL_STRING=False),
                   lambda x: x["status"].update(lastAttemptedConfigDigest="other")]:
        bad = copy.deepcopy(live)
        mutate(bad)
        try:
            make_plan(bad, desired, secret, baseline)
        except GuardError:
            count += 1
        else:
            raise AssertionError("drift was not rejected")
    adopted = copy.deepcopy(live)
    adopted["spec"].pop("values")
    adopted["spec"]["valuesFrom"] = [ref]
    adopted["metadata"].pop("annotations")
    assert make_plan(adopted, desired, secret, baseline)["already"]
    count += 1
    changed_secret = {"data": {"values.yaml": base64.b64encode(b"{}").decode()}}
    try:
        make_plan(live, desired, changed_secret, baseline)
    except GuardError:
        count += 1
    else:
        raise AssertionError("changed dedicated values were not rejected")
    for bad in [{"kind": "ConfigMap", "name": "prefix"},
                {"kind": "Secret", "name": "unknown"},
                {"kind": "Secret", "name": "prefix", "targetPath": "env"},
                {"kind": "Secret", "name": "prefix", "optional": True}]:
        try:
            validate_prefix_ref(bad, {"prefix": {}})
        except GuardError:
            count += 1
        else:
            raise AssertionError("unsupported prefix reference was not rejected")
    print(f"PASS: {count} synthetic identity, drift, type, idempotence and secret-free-payload checks")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--execute", action="store_true", help="apply guarded patches after all prevalidation and dry-runs pass")
    parser.add_argument("--self-test", action="store_true", help="run synthetic offline guard tests only")
    parser.add_argument("--kubectl", default="/home/cybervoid/.local/bin/kubectl")
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    baseline = json.loads((args.repo / "clusters/rafag/recovered-app-secrets/AdoptionBaseline.json").read_text())
    check_ready(get(args.kubectl, "kustomization.kustomize.toolkit.fluxcd.io", "recovered-app-secrets"), "Ready")
    for name in [n + "-gitops-values" for n in NAMES] + list(baseline["existingSecrets"]):
        check_ready(get(args.kubectl, "sealedsecret", name), "Synced")
    for name, expected in baseline["existingSecrets"].items():
        check_existing_secret(args.kubectl, name, expected)
    plans = []
    for name, filename in zip(NAMES, FILES):
        desired = yaml.safe_load((args.repo / "clusters/rafag/recovered-helm" / filename).read_text())
        for ref in desired["spec"].get("valuesFrom", [])[:-1]:
            validate_prefix_ref(ref, baseline["existingSecrets"])
        live = get(args.kubectl, "helmrelease", name)
        secret = get(args.kubectl, "secret", name + "-gitops-values")
        plans.append(make_plan(live, desired, secret, baseline["helmReleases"][name]))
    # All five prevalidate before the first possible write; all five dry-run first.
    for plan in plans:
        if len(plan["patch"]) > 2:
            response = run_json(args.kubectl, ["-n", "default", "patch", "helmrelease", plan["name"], "--type=json", "--dry-run=server", "--patch-file=/dev/stdin", "-o", "json"], plan["patch"])
            validate_response(response, plan)
        print(f"{plan['name']}: prevalidated; inline-input-sha256={plan['inlineValuesSha256']}; controller-config-digest={plan['controllerConfigDigest']}; already-adopted={plan['already']}")
    if not args.execute:
        print("PASS: dry-run only; no cluster state changed")
        return
    for plan in plans:
        if len(plan["patch"]) <= 2:
            print(f"{plan['name']}: already adopted; no patch")
            continue
        # The prefix is a separate object; HR resourceVersion cannot guard it.
        for ref in plan["refs"][:-1]:
            validate_prefix_ref(ref, baseline["existingSecrets"])
            check_existing_secret(args.kubectl, ref["name"], baseline["existingSecrets"][ref["name"]])
        # Do not act on a referenced Secret that drifted during the batch checks.
        fresh = get(args.kubectl, "secret", plan["name"] + "-gitops-values")
        try:
            fresh_values = json.loads(base64.b64decode(fresh["data"]["values.yaml"], validate=True))
        except (KeyError, ValueError, TypeError):
            raise GuardError("dedicated values changed before execution") from None
        if value_hash(fresh_values) != plan["inlineValuesSha256"]:
            raise GuardError("dedicated values changed before execution")
        response = run_json(args.kubectl, ["-n", "default", "patch", "helmrelease", plan["name"], "--type=json", "--patch-file=/dev/stdin", "-o", "json"], plan["patch"])
        validate_response(response, plan)
        print(f"{plan['name']}: guarded atomic patch verified")
    print("PASS: migration patches verified; await Flux Ready/current-generation and unchanged release/Pod evidence")


if __name__ == "__main__":
    try:
        main()
    except GuardError as exc:
        print(f"STOP: {exc}", file=sys.stderr)
        sys.exit(1)
    except Exception:
        # Parser/subprocess exceptions can otherwise include raw Secret bodies.
        print("STOP: unexpected error; details suppressed to protect credentials", file=sys.stderr)
        sys.exit(1)
