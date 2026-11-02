"""Offline safety and scoring checks. No model/build/cluster calls or downloads."""
import copy
import datetime
import http.server
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / (name + '.py'))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


evaluate, stage, monitor = [module(name) for name in ('evaluate', 'stage_models', 'monitor')]
MANIFEST, _ = evaluate.load_fixtures(ROOT / 'fixtures/manifest.json')


class FakeBudget:
    def check(self, reserve=0):
        pass


class ProtocolServer(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    mode = 'complete'

    def log_message(self, *args):
        pass

    def respond(self, status, body):
        self.send_response(status)
        self.send_header('Content-Type', 'text/event-stream' if isinstance(body, str) else 'application/json')
        body = body.encode() if isinstance(body, str) else json.dumps(body).encode()
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Connection', 'close')
        self.end_headers()
        self.close_connection = True
        self.wfile.write(body)

    def do_GET(self):
        self.respond(200, {'data': [{'id': 'synthetic-model'}]})

    def do_POST(self):
        payload = json.loads(self.rfile.read(int(self.headers.get('Content-Length', '0'))))
        if self.headers.get('Authorization') != 'Bearer synthetic-test-key':
            self.respond(401, {'error': 'unauthorized'})
            return
        if self.path == '/apply-template':
            self.respond(200, {'prompt': 'synthetic rendered prompt'})
            return
        if self.path == '/tokenize':
            self.respond(200, {'tokens': [1, 2, 3]})
            return
        events = [
            {'model': 'synthetic-model', 'choices': [{'delta': {'reasoning_content': 'hidden'}, 'finish_reason': None}]},
            {'model': 'synthetic-model', 'choices': [{'delta': {'content': '<think>not useful</think>'}, 'finish_reason': None}]},
            {'model': 'synthetic-model', 'choices': [{'delta': {'content': '{"facts":{}}'}, 'finish_reason': 'stop'}]},
            {'model': 'synthetic-model', 'choices': [], 'usage': {'completion_tokens': 12}},
        ]
        if self.server.mode == 'tool':
            fixture = next(f for f in MANIFEST['fixtures'] if f['id'] == 'documents-10')
            if payload['messages'][-1]['role'] == 'tool':
                assert json.loads(payload['messages'][-1]['content']) == fixture['tool']['result']
                answer = {'facts': fixture['answer_key']['facts'], 'citations': fixture['answer_key']['required_citations'],
                          'explanation': 'Read synthetic local addendum.'}
                events = [{'model': 'synthetic-model', 'choices': [{'delta': {'content': json.dumps(answer)}, 'finish_reason': 'stop'}]}]
            else:
                events = [{'model': 'synthetic-model', 'choices': [{'delta': {'tool_calls': [
                    {'index': 0, 'id': 'fake-call', 'type': 'function', 'function': {'name': 'lookup_record', 'arguments': '{"record_id":'}}]}, 'finish_reason': None}]},
                    {'model': 'synthetic-model', 'choices': [{'delta': {'tool_calls': [
                        {'index': 0, 'function': {'arguments': '"documents-10"}'}}]}, 'finish_reason': 'tool_calls'}]}]
        if self.server.mode == 'wrong-model':
            for event in events:
                event['model'] = 'other-model'
        result = ''.join('data: ' + json.dumps(event) + '\n\n' for event in events)
        if self.server.mode != 'partial':
            result += 'data: [DONE]\n\n'
        self.respond(200, result)


class ProtocolTests(unittest.TestCase):
    def setUp(self):
        self.server = http.server.HTTPServer(('127.0.0.1', 0), ProtocolServer)
        self.server.mode = 'complete'
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.api = evaluate.LocalAPI('http://127.0.0.1:' + str(self.server.server_port) + '/v1',
                                     'synthetic-test-key', FakeBudget())

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(2)

    def test_auth_denial_then_real_stream_excludes_hidden_reasoning(self):
        self.api.authenticate('synthetic-model')
        result = self.api.request('/v1/chat/completions', {'model': 'synthetic-model'}, stream=True)
        self.assertEqual(result['content'], '{"facts":{}}')
        self.assertEqual(result['reasoning_characters'], 6)
        self.assertIsNotNone(result['first_useful_s'])
        self.assertNotIn('synthetic-test-key', json.dumps(result))

    def test_disconnect_and_effective_model_mismatch_are_failures(self):
        for mode in ('partial', 'wrong-model'):
            with self.subTest(mode=mode):
                self.server.mode = mode
                with self.assertRaises(ValueError):
                    self.api.request('/v1/chat/completions', {'model': 'synthetic-model'}, stream=True)

    def test_nonlocal_and_credential_urls_refused(self):
        for url in ('https://example.com/v1', 'https://8.8.8.8/v1', 'http://user:pass@127.0.0.1/v1',
                    'http://127.0.0.1/v1?key=bad', 'http://169.254.169.254/v1'):
            with self.subTest(url=url), self.assertRaises(ValueError):
                evaluate.LocalAPI(url, 'x', FakeBudget())

    def test_real_streamed_tool_arguments_local_execution_and_continuation(self):
        self.server.mode = 'tool'
        fixture = next(f for f in MANIFEST['fixtures'] if f['id'] == 'documents-10')
        profile = {'model': 'synthetic-model', 'context': 8192, 'thinking': 'direct', 'temperature': 0,
                   'overhead_tools': []}
        result = evaluate.infer(self.api, fixture, [evaluate.messages_for(fixture, ROOT / 'fixtures')], profile, 42, 512)
        self.assertTrue(result['tool_roundtrip'])
        self.assertTrue(evaluate.score_response(result['content'], fixture)['objective_checks_passed'])


class FixtureTests(unittest.TestCase):
    def test_integrity_and_frozen_coverage(self):
        self.assertEqual(len(MANIFEST['fixtures']), 40)
        self.assertEqual(sum(f['modality'] == 'image' for f in MANIFEST['fixtures']), 12)
        self.assertEqual(sum('tool' in f for f in MANIFEST['fixtures']), 4)
        for fixture in MANIFEST['fixtures']:
            answer = {'facts': fixture['answer_key']['facts'],
                      'citations': fixture['answer_key']['required_citations'], 'explanation': 'Grounded synthetic answer.'}
            if 'code_tests' not in fixture:
                self.assertTrue(evaluate.score_response(json.dumps(answer), fixture)['objective_checks_passed'], fixture['id'])

    def test_wrong_money_missing_page_and_boolean_types_fail(self):
        fixture = next(f for f in MANIFEST['fixtures'] if f['id'] == 'documents-03')
        answer = {'facts': copy.deepcopy(fixture['answer_key']['facts']),
                  'citations': fixture['answer_key']['required_citations'], 'explanation': 'review'}
        answer['facts']['whole_document_read'] = True
        self.assertFalse(evaluate.score_response(json.dumps(answer), fixture)['objective_checks_passed'])
        self.assertFalse(evaluate.equal_fact(True, 1))
        self.assertFalse(evaluate.equal_fact(1, True))
        self.assertFalse(evaluate.equal_fact(float('nan'), 30))

    def test_fake_tool_rejects_schema_or_external_tool(self):
        fixture = next(f for f in MANIFEST['fixtures'] if 'tool' in f)
        call = {'id': 'test', 'type': 'function', 'function': {'name': 'lookup_record',
                 'arguments': json.dumps({'record_id': fixture['id']})}}
        self.assertEqual(json.loads(evaluate.execute_fake_tool(call, fixture)['content']), fixture['tool']['result'])
        for bad in ({'record_id': '../secrets'}, {'record_id': fixture['id'], 'extra': 'x'}):
            call['function']['arguments'] = json.dumps(bad)
            with self.assertRaises(ValueError):
                evaluate.execute_fake_tool(call, fixture)

    def test_context_counts_history_tools_and_stops_before_inference(self):
        class AccountingAPI:
            def request(self, route, payload, **kwargs):
                if route == '/apply-template':
                    self.payload = payload
                    return {'status': 200, 'data': {'prompt': 'rendered'}}
                return {'status': 200, 'data': {'tokens': list(range(4000))}}
        api = AccountingAPI()
        with self.assertRaises(evaluate.ContextExceeded):
            evaluate.count_context(api, [{'role': 'system', 'content': 'history'}], [{'type': 'function'}],
                                   {'context': 4096, 'thinking': 'direct'}, 512)
        self.assertEqual(api.payload['tools'], [{'type': 'function'}])
        with self.assertRaises(ValueError):
            evaluate.count_context(api, [{'role': 'user', 'content': [{'type': 'image_url'}]}], [],
                                   {'context': 8192, 'thinking': 'direct'}, 512)


class CodeTests(unittest.TestCase):
    def test_meaningful_cases_and_mutation_failure(self):
        fixture = next(f for f in MANIFEST['fixtures'] if f['id'] == 'coding-05')
        self.assertTrue(evaluate.check_code('def unique_total(values):\n return sum(set(values))', fixture['code_tests']))
        self.assertFalse(evaluate.check_code('def unique_total(values):\n return sum(values)', fixture['code_tests']))
        merge = next(f for f in MANIFEST['fixtures'] if f['id'] == 'coding-06')
        good_merge = ('def merge_counts(left,right):\n result={}\n for key in left:\n  result[key]=left[key]\n'
                      ' for key in right:\n  if key in result:\n   result[key]+=right[key]\n'
                      '  else:\n   result[key]=right[key]\n return result')
        self.assertTrue(evaluate.check_code(good_merge, merge['code_tests']))
        code = 'def merge_counts(left,right):\n return {k:sum([v for d in [left,right] for key,v in d if key==k]) for k in []}'
        self.assertFalse(evaluate.check_code(code, merge['code_tests']))
        mutation = 'def unique_total(values):\n values[0]=99\n return sum(set(values))'
        self.assertFalse(evaluate.check_code(mutation, fixture['code_tests']))

    def test_files_network_imports_attributes_dynamic_calls_refused(self):
        for code in ('def f():\n import os\n return 1', 'def f():\n return open("/etc/passwd")',
                     'def f():\n return (1).__class__', 'def f():\n return eval("1")',
                     'def f():\n return __builtins__', '@sum\ndef f():\n return 1'):
            with self.subTest(code=code), self.assertRaises(ValueError):
                evaluate.validate_code(code)

    def test_unbounded_loop_is_bounded_by_resource_limits(self):
        tests = {'function': 'f', 'cases': [[[1], 1]]}
        self.assertFalse(evaluate.check_code('def f(x):\n return f(x)', tests))


class StateTests(unittest.TestCase):
    def test_persistent_budget_cannot_reset_and_stop_file_blocks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            start = datetime.datetime.now(datetime.timezone.utc).isoformat()
            budget = evaluate.Budget(root / 'budget.json', start, root / 'stop')
            budget.check(120)
            saved = json.loads((root / 'budget.json').read_text())
            budget.lock.close()
            resumed = evaluate.Budget(root / 'budget.json', start, root / 'stop')
            self.assertEqual(resumed.deadline, saved['deadline_epoch'])
            (root / 'stop').write_text('operator stop')
            with self.assertRaises(evaluate.Stopped):
                resumed.check()
            resumed.lock.close()
            with self.assertRaises(ValueError):
                evaluate.Budget(root / 'budget.json', start + '0', root / 'stop')

    def test_started_checkpoint_is_not_replayed_or_marked_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'results.jsonl'
            results = evaluate.Results(path, 'test')
            record = {'key': 'quality/documents-01/0', 'phase': 'quality', 'status': 'started'}
            results.append(record)
            result = evaluate.run_trial(None, MANIFEST['fixtures'][0], [], {}, results, 'quality', record['key'], 0)
            self.assertEqual(result['status'], 'started')
            self.assertFalse(evaluate.summary(results, MANIFEST, None)['quality_passed'])
            results.stream.close()
            with self.assertRaises(ValueError):
                evaluate.Results(path, 'changed-profile')

    def test_quality_cannot_hide_weak_category_in_overall_mean(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            results = evaluate.Results(root / 'results.jsonl', 'test')
            reviews = []
            for fixture in MANIFEST['fixtures']:
                for repeat in range(3):
                    key = 'quality/' + fixture['id'] + '/' + str(repeat)
                    results.append({'key': key, 'phase': 'quality', 'status': 'complete',
                                    'scoring': {'objective_checks_passed': True}})
                    reviews.append({'identity': 'test', 'key': key, 'score': 2 if fixture['category'] == 'coding' else 4,
                                    'critical_failure': False, 'reviewer': 'test', 'reason': 'synthetic review'})
            path = root / 'reviews.jsonl'
            path.write_text(''.join(json.dumps(r) + '\n' for r in reviews))
            report = evaluate.summary(results, MANIFEST, path)
            self.assertFalse(report['quality_passed'])
            self.assertEqual(report['quality']['coding']['majority_passing_tasks'], 0)
            self.assertTrue(report['quality']['documents']['passed'])
            results.stream.close()


class StagingTests(unittest.TestCase):
    def models(self):
        return [{'repo': 'synthetic/repo', 'revision': 'a' * 40, 'path': str(index) + '.gguf',
                 'bytes': 5, 'sha256': stage.hashlib.sha256(b'abcde').hexdigest()} for index in range(4)]

    def test_lock_and_path_guards(self):
        for field, value in [('path', '../escape'), ('revision', 'main'), ('sha256', 'bad')]:
            models = self.models()
            models[0][field] = value
            with self.assertRaises(ValueError):
                stage.validate_models({'models': models})
        models = self.models()
        models[1]['local_name'] = '0.gguf'
        with self.assertRaises(ValueError):
            stage.validate_models({'models': models})

    def test_verified_resume_charges_prefix_and_hashes_before_rename(self):
        class Response(io.BytesIO):
            status = 200
            headers = {'Content-Length': '5'}
        class Opener:
            def open(self, url, timeout):
                self.url = url
                return Response(b'abcde')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            models_dir = root / 'models'
            models_dir.mkdir()
            (models_dir / '0.gguf.part').write_bytes(b'ab')
            state = {'transferred_bytes': 0}
            opener = Opener()
            stager = stage.Stager(models_dir, root / 'state.json', state, opener)
            with patch.object(stager, 'guard'):
                self.assertEqual(stager.stage(stage.validate_models({'models': self.models()})[0]), 'staged')
            self.assertEqual((models_dir / '0.gguf').read_bytes(), b'abcde')
            self.assertEqual(state['transferred_bytes'], 5)
            self.assertIn('/resolve/' + 'a' * 40 + '/', opener.url)
            self.assertFalse((models_dir / '0.gguf.part').exists())

    def test_mismatched_partial_not_appended_and_transfer_cap_persists(self):
        class Response(io.BytesIO):
            status = 200
            headers = {'Content-Length': '5'}
        class Opener:
            def open(self, *args, **kwargs):
                return Response(b'abcde')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / '0.gguf.part').write_bytes(b'XX')
            stager = stage.Stager(root, root / 'state.json', {'transferred_bytes': 0}, Opener())
            with patch.object(stager, 'guard'), self.assertRaises(ValueError):
                stager.stage(stage.validate_models({'models': self.models()})[0])
            self.assertEqual((root / '0.gguf.part').read_bytes(), b'XX')
            stager.state['transferred_bytes'] = stage.TRANSFER_LIMIT
            with self.assertRaises(ValueError):
                stager.charged_read(Response(b'abcde'), 1)

    def test_symlink_and_untrusted_redirect_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / '0.gguf.part').symlink_to(root / 'outside')
            stager = stage.Stager(root, root / 'state.json', {'transferred_bytes': 0})
            with self.assertRaises(ValueError):
                stager.stage(stage.validate_models({'models': self.models()})[0])
        handler = stage.TrustedRedirect()
        with self.assertRaises(ValueError):
            handler.redirect_request(None, None, 302, '', {}, 'https://evil.example/file')


class MonitorTests(unittest.TestCase):
    def sample(self, **kwargs):
        return {'root_free_bytes': 100 * monitor.GIB, 'mem_available_bytes': 30 * monitor.GIB,
                'gpu_temperature_c': 60, **kwargs}

    def test_sustained_thresholds_and_recovery_reset(self):
        thresholds = monitor.Thresholds()
        self.assertIsNone(thresholds.evaluate(self.sample(gpu_temperature_c=85), 0))
        self.assertIsNone(thresholds.evaluate(self.sample(gpu_temperature_c=85), 29))
        self.assertIsNone(thresholds.evaluate(self.sample(), 30))
        self.assertIsNone(thresholds.evaluate(self.sample(gpu_temperature_c=85), 31))
        self.assertEqual(thresholds.evaluate(self.sample(gpu_temperature_c=85), 61), 'gpu_temperature')
        memory = monitor.Thresholds()
        self.assertIsNone(memory.evaluate(self.sample(mem_available_bytes=23 * monitor.GIB), 10))
        self.assertEqual(memory.evaluate(self.sample(mem_available_bytes=23 * monitor.GIB), 40), 'host_memory')

    def test_hardware_owner_and_disk_stop_immediately(self):
        for changed, expected in [({'xid': True}, 'new_xid'), ({'unexpected_gpu_processes': 1}, 'unexpected_gpu_owner'),
                                  ({'root_free_bytes': 74 * monitor.GIB}, 'root_floor')]:
            self.assertEqual(monitor.Thresholds().evaluate(self.sample(**changed), 0), expected)


if __name__ == '__main__':
    unittest.main()
