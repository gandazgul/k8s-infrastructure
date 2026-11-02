#!/usr/bin/env python3
"""Read-only, credential-safe ownership census of the recovered rafag cluster."""

import argparse
from collections import Counter, defaultdict
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
KUSTOMIZATION = 'kustomize.toolkit.fluxcd.io'
HELM = 'helm.toolkit.fluxcd.io'
SOURCE = 'source.toolkit.fluxcd.io'
CNPG = 'postgresql.cnpg.io'
QUERIES = (
    'kustomizations.' + KUSTOMIZATION, 'helmreleases.' + HELM,
    'gitrepositories.' + SOURCE, 'deployments.apps', 'daemonsets.apps',
    'statefulsets.apps', 'replicasets.apps', 'replicationcontrollers',
    'cronjobs.batch', 'jobs.batch', 'pods', 'nodes', 'clusters.' + CNPG,
    'persistentvolumes', 'persistentvolumeclaims',
)
SEEDS = {
    (KUSTOMIZATION, 'Kustomization', 'kube-system', 'kube-system'):
        ('infrastructure/kube-system', 'infrastructure/setup/KubeSystem.yaml'),
    (KUSTOMIZATION, 'Kustomization', 'kube-system', 'sealed-secret'):
        ('clusters/rafag/sealed-secret', 'clusters/rafag/sealed-secret/Reconciliation.yaml'),
    (KUSTOMIZATION, 'Kustomization', 'kube-system', 'rafag'):
        ('clusters/rafag', 'clusters/rafag/ClusterKustomization.yaml'),
}
BOOTSTRAP = {
    ('apps', 'Deployment', 'kube-system', 'coredns'): 'install-k8s/2-configK8SControlPlane.sh',
    ('apps', 'DaemonSet', 'kube-system', 'kube-proxy'): 'install-k8s/2-configK8SControlPlane.sh',
    ('apps', 'DaemonSet', 'kube-flannel', 'kube-flannel-ds'): 'install-k8s/2-configK8SControlPlane.sh',
    **{('apps', 'Deployment', 'kube-system', name): 'infrastructure/setup/install-flux.sh'
       for name in ('source-controller', 'kustomize-controller', 'helm-controller',
                    'notification-controller')},
}
HELM_HOLDS = {(HELM, 'HelmRelease', 'default', name)
              for name in ('home-assistant', 'sftpgo')}
HOLDS = {
    ('', 'Pod', 'default', 'immich-private-api'):
        'Restricted Immich recovery; local database and read-only photos; not adopted.',
    ('', 'Pod', 'default', 'runwield-paperless-web'):
        'RunWield Paperless recovery Pod; failed runtime is not repaired by ownership audit.',
    ('batch', 'Job', 'default', 'sonarr-transmission-private'):
        'Long-running combined recovery Job; no controller migration approved.',
    (CNPG, 'Cluster', 'default', 'recovery-immich'):
        'Recovery database; preserve deliberate hibernation; no fresh bootstrap.',
    (CNPG, 'Cluster', 'default', 'recovery-paperless'):
        'Recovery database; database adoption/repair is a separate reviewed phase.',
}


class AuditError(Exception):
    """Only deliberately sanitized messages may reach the report."""


def key(obj):
    api = obj['apiVersion']
    meta = obj['metadata']
    return (api.split('/')[0] if '/' in api else '', obj['kind'],
            meta.get('namespace', ''), meta['name'])


def ref(identity):
    group, kind, namespace, name = identity
    return {'group': group, 'kind': kind, 'namespace': namespace, 'name': name}


def label(identity):
    return '/'.join((identity[1], identity[2] or '_cluster', identity[3]))


def sha(revision):
    match = re.search(r'(?:sha1:|sha256:)?([a-f0-9]{64}|[a-f0-9]{40})$', revision or '')
    return match.group(1) if match else None


def run(args, cwd=None):
    try:
        result = subprocess.run(args, cwd=cwd, capture_output=True, text=True,
                                timeout=45, check=False)
    except (OSError, subprocess.TimeoutExpired):
        raise AuditError('Read-only command unavailable or timed out; raw output suppressed.') from None
    if result.returncode:
        raise AuditError('Read-only command failed; raw stdout/stderr suppressed.')
    return result.stdout


def ready(obj):
    """Require a True Ready and a current generation, never stale Healthy alone."""
    status = obj.get('status', {})
    generation = obj['metadata'].get('generation')
    condition = next((c for c in status.get('conditions', []) if c['type'] == 'Ready'), {})
    observed = status.get('observedGeneration')
    ready_observed = condition.get('observedGeneration')
    generations = [g for g in (observed, ready_observed) if g is not None]
    return {'ready': condition.get('status') == 'True', 'generation': generation,
            'observedGeneration': observed, 'readyObservedGeneration': ready_observed,
            'currentGeneration': bool(generations) and generation is not None
                                 and all(g == generation for g in generations),
            'reason': condition.get('reason'),
            'suspended': bool(obj.get('spec', {}).get('suspend', False))}


def collect(kubectl):
    objects = {}
    counts = {}
    for resource in QUERIES:
        try:
            response = json.loads(run([kubectl, '--request-timeout=20s', 'get',
                                       resource, '-A', '-o', 'json']))
            items = response['items']
            counts[resource] = len(items)
            for item in items:
                objects[key(item)] = item
        except (ValueError, KeyError, TypeError):
            raise AuditError('Invalid resource-list response for ' + resource) from None
        except AuditError as error:
            raise AuditError('Could not inventory ' + resource + ': ' + str(error)) from None
    return objects, counts


def audit(objects, counts, expected_sha, expected_source, strict):
    parents = defaultdict(list)
    edges = []
    issues = []
    flux = {}
    sources = {}
    inventory_sets = {}

    def edge(child, parent, evidence):
        if child != parent:
            parents[child].append((parent, evidence))
        if child in objects:
            edges.append({'child': ref(child), 'parent': ref(parent), 'evidence': evidence})

    for identity, obj in objects.items():
        if identity[0] == SOURCE and identity[1] == 'GitRepository':
            state = ready(obj)
            revision = obj.get('status', {}).get('artifact', {}).get('revision')
            state.update(ref(identity), revision=revision, sha=sha(revision))
            state['valid'] = (state['ready'] and state['currentGeneration']
                              and not state['suspended'] and state['sha'] == expected_sha)
            sources[identity] = state
        if identity[0] in (KUSTOMIZATION, HELM):
            entries = obj.get('status', {}).get('inventory', {}).get('entries', [])
            inventory_sets[identity] = set()
            for entry in entries:
                namespace, separator, remainder = entry.get('id', '').partition('_')
                parts = remainder.rsplit('_', 2)
                if not separator or len(parts) != 3:
                    issues.append(label(identity) + ': malformed inventory identity')
                    continue
                name, group, kind = parts
                # Flux encodes colons in RBAC object names as double underscores.
                child = (group, kind, namespace, name.replace('__', ':'))
                inventory_sets[identity].add(child)
                edge(child, identity, 'status.inventory')
        for owner in obj['metadata'].get('ownerReferences', []):
            api = owner.get('apiVersion', '')
            group = api.split('/')[0] if '/' in api else ''
            owner_namespace = '' if owner.get('kind') == 'Node' else identity[2]
            parent = (group, owner.get('kind'), owner_namespace, owner.get('name'))
            if parent in objects and owner.get('uid') == objects[parent]['metadata']['uid']:
                edge(identity, parent, 'ownerReference UID verified')

    for identity, obj in objects.items():
        if identity[0] != KUSTOMIZATION:
            continue
        spec = obj.get('spec', {})
        source_ref = spec.get('sourceRef', {})
        source_key = (SOURCE, source_ref.get('kind'), source_ref.get('namespace', identity[2]),
                      source_ref.get('name'))
        edges.append({'child': ref(identity), 'parent': ref(source_key), 'evidence': 'spec.sourceRef'})
        state = ready(obj)
        applied = obj.get('status', {}).get('lastAppliedRevision')
        path = spec.get('path', '').removeprefix('./').rstrip('/')
        state.update(ref(identity), path=path, source=ref(source_key), appliedRevision=applied,
                     appliedSHA=sha(applied), inventoryCount=len(inventory_sets.get(identity, ())))
        state['valid'] = bool(state['ready'] and state['currentGeneration'] and not state['suspended']
                              and sha(applied) == expected_sha and source_key in sources
                              and sources[source_key]['valid'] and source_key == expected_source
                              and path and (ROOT / path).is_dir())
        state['dependencies'] = []
        for dependency in spec.get('dependsOn', []):
            dep_key = (KUSTOMIZATION, 'Kustomization', dependency.get('namespace', identity[2]),
                       dependency.get('name'))
            state['dependencies'].append(ref(dep_key))
            edges.append({'child': ref(identity), 'parent': ref(dep_key), 'evidence': 'spec.dependsOn'})
            if dep_key not in objects:
                state['valid'] = False
                issues.append(label(identity) + ': missing declared dependency ' + label(dep_key))
        flux[identity] = state
        if not state['valid']:
            issues.append(label(identity) + ': not Ready/current/source-matched at expected SHA, or missing local path')

    for identity, state in sources.items():
        if identity == expected_source and not state['valid']:
            issues.append(label(identity) + ': source not Ready/current at expected SHA')
    if expected_source not in sources:
        issues.append('Expected GitRepository is absent')

    def paths(identity, seen=()):
        if identity in seen:
            return []
        if identity in SEEDS:
            path, entrypoint = SEEDS[identity]
            if (flux.get(identity, {}).get('path') == path and
                    identity in inventory_sets.get(identity, ()) and (ROOT / entrypoint).is_file()):
                return [[identity]]
        result = []
        for parent, _ in parents.get(identity, []):
            for chain in paths(parent, (*seen, identity)):
                result.append([identity, *chain])
        return result

    def path_valid(chain):
        for identity in chain:
            if identity[0] == KUSTOMIZATION and not flux.get(identity, {}).get('valid'):
                return False
            if identity[0] == HELM:
                state = ready(objects[identity])
                if not (state['ready'] and state['currentGeneration'] and not state['suspended']):
                    return False
        return True

    # Audit Helm declaration ownership separately from whether its release is deliberately held.
    helm_states = []
    for identity, obj in objects.items():
        if identity[0] != HELM:
            continue
        state = ready(obj)
        chains = paths(identity)
        state.update(ref(identity), inventoryCount=len(inventory_sets.get(identity, ())),
                     declarationTracked=any(path_valid(c[1:]) for c in chains))
        state['intentionalControllerHold'] = identity in HELM_HOLDS
        helm_states.append(state)
        if state['suspended'] != (identity in HELM_HOLDS):
            issues.append(label(identity) + ': controller suspend state differs from explicit hold policy')
        if not state['declarationTracked']:
            issues.append(label(identity) + ': HelmRelease has no active GitOps declaration chain')
        if not state['suspended'] and not (state['ready'] and state['currentGeneration']):
            issues.append(label(identity) + ': unsuspended HelmRelease is not Ready/current')

    resources = []
    excluded_pods = Counter()
    report_kinds = {'Deployment', 'DaemonSet', 'StatefulSet', 'ReplicationController',
                    'CronJob', 'Job', 'Pod', 'PersistentVolume', 'PersistentVolumeClaim', 'Cluster'}
    for identity, obj in sorted(objects.items()):
        if identity[1] not in report_kinds:
            continue
        if identity[1] == 'Pod' and any(evidence == 'ownerReference UID verified'
                                         for _, evidence in parents.get(identity, [])):
            excluded_pods['ownedPods'] += 1
            continue
        row = {**ref(identity), 'uid': obj['metadata']['uid']}
        hold = HOLDS.get(identity)
        hold_origin = identity if hold else None
        if identity[1] == 'PersistentVolumeClaim':
            for parent, evidence in parents.get(identity, []):
                if parent in HOLDS and evidence == 'ownerReference UID verified':
                    hold, hold_origin = HOLDS[parent], parent
        chains = paths(identity)
        active = [chain for chain in chains if path_valid(chain)]
        if hold:
            row.update(classification='ExplicitRecoveryHold', reason=hold, holdOrigin=ref(hold_origin))
            if identity[0] == CNPG:
                row['hibernated'] = any(c.get('type') == 'cnpg.io/hibernation' and c.get('status') == 'True'
                                         for c in obj.get('status', {}).get('conditions', []))
                if identity[3] == 'recovery-immich' and not row['hibernated']:
                    issues.append(label(identity) + ': deliberate hibernation is not observed')
        elif active:
            chain = min(active, key=len)
            leaf = next(x for x in chain if x[0] == KUSTOMIZATION)
            row.update(classification='ActiveGitOps', leafPath=flux[leaf]['path'],
                       leafOwner=ref(leaf), ancestry=[ref(x) for x in chain],
                       appliedSHA=flux[leaf]['appliedSHA'], source=flux[leaf]['source'])
        elif identity in BOOTSTRAP and (ROOT / BOOTSTRAP[identity]).is_file():
            row.update(classification='BootstrapManaged', repoEntrypoint=BOOTSTRAP[identity],
                       reason='Installer-managed; not an active Flux ownership claim.')
        elif chains:
            row.update(classification='GitOpsNotCurrent', ancestry=[ref(x) for x in min(chains, key=len)],
                       reason='Inventory ancestry exists, but an owner/source is not current or is suspended.')
        else:
            row.update(classification='UnexpectedUnowned', reason='No verified inventory/bootstrap/hold ancestry.')
        resources.append(row)

    classifications = Counter(row['classification'] for row in resources)
    if classifications['UnexpectedUnowned']:
        issues.append('Unexpected unowned workload/storage objects exist')
    if classifications['GitOpsNotCurrent']:
        issues.append('Inventoried workload/storage objects have inactive/noncurrent ownership')
    if strict and classifications['ExplicitRecoveryHold']:
        issues.append('Strict mode: explicit recovery holds prevent full GitOps completion')
    return {
        'schemaVersion': 1, 'generatedAt': datetime.now(timezone.utc).isoformat(),
        'readOnly': True, 'strict': strict, 'expectedSHA': expected_sha,
        'expectedSource': ref(expected_source), 'passed': not issues,
        'fullGitOpsCompletion': not issues and not classifications['ExplicitRecoveryHold'],
        'counts': {'queried': counts, 'classified': dict(sorted(classifications.items())),
                   'excluded': dict(excluded_pods)},
        'issues': sorted(set(issues)), 'sources': list(sources.values()),
        'kustomizations': list(flux.values()), 'helmReleases': helm_states,
        'bootstrapSeeds': [{'resource': ref(k), 'path': v[0], 'repoEntrypoint': v[1]} for k, v in SEEDS.items()],
        'recoveryHoldPolicy': [{'resource': ref(k), 'reason': reason, 'present': k in objects}
                               for k, reason in HOLDS.items()],
        'resources': resources, 'dependencyGraph': edges,
        'limitations': [
            'Sequential non-atomic snapshot; reconciliation can advance during collection.',
            'Ownership audit, not runtime health, semantic spec equality, data/backup or rebuild proof.',
            'Owner-referenced Pods are excluded from workload counts; ReplicaSets are ancestry-only.',
            'No Secret requests; response bodies stay in memory and only allowlisted metadata/status fields are emitted.',
            'Local paths/installer references are checked for existence, not rendered or applied by this helper.',
            'Explicit named bootstrap/hold policy is rafag-specific; no prefix-based exception matching.',
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kubectl', default='kubectl')
    parser.add_argument('--expected-sha', help='Exact Git source commit; defaults to repository HEAD.')
    parser.add_argument('--expected-source', default='kube-system/k8s-infrastructure', metavar='NAMESPACE/NAME')
    parser.add_argument('--strict', action='store_true', help='Also fail on any explicit recovery hold.')
    args = parser.parse_args()
    try:
        expected = args.expected_sha or run(['git', 'rev-parse', 'HEAD'], cwd=ROOT).strip()
        if not re.fullmatch(r'[a-f0-9]{40}|[a-f0-9]{64}', expected):
            raise AuditError('Expected SHA must be a full lowercase Git object ID.')
        source_parts = args.expected_source.split('/')
        if len(source_parts) != 2 or not all(source_parts):
            raise AuditError('Expected source must be NAMESPACE/NAME.')
        objects, counts = collect(args.kubectl)
        report = audit(objects, counts, expected,
                       (SOURCE, 'GitRepository', *source_parts), args.strict)
        print(json.dumps(report, indent=2, sort_keys=True))
        return 0 if report['passed'] else 1
    except AuditError as error:
        print(json.dumps({'readOnly': True, 'passed': False, 'error': str(error)}))
        return 2


if __name__ == '__main__':
    sys.exit(main())
