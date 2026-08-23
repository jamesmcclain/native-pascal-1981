"""Tests for tools/pascal1981_completion_proxy.py.

Pure-function tests (schema validation, prompt construction, sanitization)
run directly. The HTTP layer is tested end-to-end against a real
ForkingHTTPServer instance bound to an ephemeral loopback port, with
`call_upstream` monkeypatched so no network call ever leaves the process --
there is no live OpenAI-compatible backend in CI.
"""

import http.client
import importlib.util
import json
import os
import sys
import unittest
from pathlib import Path
from unittest import mock

REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / 'tools' / 'pascal1981_completion_proxy.py'

_spec = importlib.util.spec_from_file_location('pascal1981_completion_proxy',
                                               MODULE_PATH)
proxy = importlib.util.module_from_spec(_spec)
sys.modules['pascal1981_completion_proxy'] = proxy
_spec.loader.exec_module(proxy)


def chat_response(content,
                  model='test-model',
                  request_id='abc123',
                  finish_reason='stop',
                  reasoning_content=None):
    """Build a /chat/completions-shaped upstream JSON body for mocks."""
    message = {'role': 'assistant', 'content': content}
    if reasoning_content is not None:
        message['reasoning_content'] = reasoning_content
    return {
        'id': request_id,
        'model': model,
        'choices': [{
            'message': message,
            'finish_reason': finish_reason,
        }],
    }


class ValidateRequestTests(unittest.TestCase):

    def test_accepts_well_formed_request(self):
        goal, buffer, line, column = proxy.validate_request(
            {
                'goal': 'finish it',
                'buffer': 'VAR x: INTEGER;\n',
                'cursor': {
                    'line': 1,
                    'column': 5
                },
            },
            buffer_limit=1000)
        self.assertEqual((goal, buffer, line, column),
                         ('finish it', 'VAR x: INTEGER;\n', 1, 5))

    def test_goal_defaults_to_empty_string(self):
        goal, *_rest = proxy.validate_request(
            {
                'buffer': 'x',
                'cursor': {
                    'line': 1,
                    'column': 1
                }
            },
            buffer_limit=1000)
        self.assertEqual(goal, '')

    def test_rejects_non_object_body(self):
        with self.assertRaises(proxy.RequestError):
            proxy.validate_request(['not', 'an', 'object'], buffer_limit=1000)

    def test_rejects_missing_buffer(self):
        with self.assertRaises(proxy.RequestError):
            proxy.validate_request({'cursor': {
                'line': 1,
                'column': 1
            }},
                                   buffer_limit=1000)

    def test_rejects_non_string_buffer(self):
        with self.assertRaises(proxy.RequestError):
            proxy.validate_request(
                {
                    'buffer': 123,
                    'cursor': {
                        'line': 1,
                        'column': 1
                    }
                },
                buffer_limit=1000)

    def test_rejects_oversized_buffer(self):
        with self.assertRaises(proxy.RequestError):
            proxy.validate_request(
                {
                    'buffer': 'x' * 10,
                    'cursor': {
                        'line': 1,
                        'column': 1
                    }
                },
                buffer_limit=5)

    def test_rejects_missing_cursor(self):
        with self.assertRaises(proxy.RequestError):
            proxy.validate_request({'buffer': 'x'}, buffer_limit=1000)

    def test_rejects_non_integer_line(self):
        with self.assertRaises(proxy.RequestError):
            proxy.validate_request(
                {
                    'buffer': 'x',
                    'cursor': {
                        'line': '1',
                        'column': 1
                    }
                },
                buffer_limit=1000)

    def test_rejects_zero_or_negative_line_or_column(self):
        with self.assertRaises(proxy.RequestError):
            proxy.validate_request(
                {
                    'buffer': 'x',
                    'cursor': {
                        'line': 0,
                        'column': 1
                    }
                },
                buffer_limit=1000)
        with self.assertRaises(proxy.RequestError):
            proxy.validate_request(
                {
                    'buffer': 'x',
                    'cursor': {
                        'line': 1,
                        'column': -1
                    }
                },
                buffer_limit=1000)

    def test_rejects_boolean_line(self):
        # bool is a subclass of int in Python; must not slip through.
        with self.assertRaises(proxy.RequestError):
            proxy.validate_request(
                {
                    'buffer': 'x',
                    'cursor': {
                        'line': True,
                        'column': 1
                    }
                },
                buffer_limit=1000)


class ComputePrefixTests(unittest.TestCase):

    def test_end_of_first_line(self):
        self.assertEqual(proxy.compute_prefix('abc\ndef', 1, 4), 'abc')

    def test_middle_of_line(self):
        self.assertEqual(proxy.compute_prefix('abc\ndef', 2, 2), 'abc\nd')

    def test_column_clamped_to_line_length(self):
        self.assertEqual(proxy.compute_prefix('abc\ndef', 1, 999), 'abc')

    def test_line_clamped_to_buffer_length(self):
        # Line clamps to the last line ("def"); column 1 on that line means
        # nothing of it is included yet.
        self.assertEqual(proxy.compute_prefix('abc\ndef', 999, 1), 'abc\n')

    def test_line_and_column_clamped_to_end_of_buffer(self):
        self.assertEqual(proxy.compute_prefix('abc\ndef', 999, 999),
                         'abc\ndef')

    def test_single_line_buffer(self):
        self.assertEqual(proxy.compute_prefix('hello', 1, 3), 'he')


class BuildPromptTests(unittest.TestCase):

    def test_empty_goal_returns_prefix_unchanged(self):
        self.assertEqual(proxy.build_prompt('', 'VAR x'), 'VAR x')
        self.assertEqual(proxy.build_prompt('   ', 'VAR x'), 'VAR x')

    def test_goal_becomes_leading_comment(self):
        self.assertEqual(proxy.build_prompt('finish the statement', 'VAR x'),
                         '{ finish the statement }\nVAR x')

    def test_goal_newlines_collapsed(self):
        self.assertEqual(proxy.build_prompt('line one\nline two', 'p'),
                         '{ line one line two }\np')


class GrammarContextTests(unittest.TestCase):

    def test_build_prompt_without_grammar_unchanged(self):
        self.assertEqual(proxy.build_prompt('', 'VAR x', grammar=''), 'VAR x')

    def test_build_prompt_prepends_grammar_block(self):
        result = proxy.build_prompt('', 'VAR x', grammar='rule = "X" ;')
        self.assertTrue(result.startswith(proxy._GRAMMAR_HEADER))
        self.assertIn('rule = "X" ;', result)
        self.assertIn(proxy._GRAMMAR_FOOTER, result)
        self.assertTrue(result.endswith('VAR x'))

    def test_grammar_containing_pascal_comment_delimiters_not_truncated(self):
        # The real grammar doc contains both '{ }' and '(* *)' as EBNF /
        # worked-example syntax; wrapping it in either as a Pascal comment
        # would let the grammar's own content close the wrapper early.
        grammar = 'a = { "x" } ;\n(* an example comment *)\nb = "y" ;'
        result = proxy.build_prompt('', 'p', grammar=grammar)
        self.assertIn('a = { "x" } ;', result)
        self.assertIn('(* an example comment *)', result)
        self.assertIn('b = "y" ;', result)

    def test_goal_and_grammar_both_present(self):
        result = proxy.build_prompt('finish it', 'p', grammar='g = "z" ;')
        self.assertIn(proxy._GRAMMAR_HEADER, result)
        self.assertIn('{ finish it }\np', result)
        # Grammar block comes first, then the goal comment, then the prefix.
        self.assertLess(result.index(proxy._GRAMMAR_HEADER),
                        result.index('{ finish it }'))

    def test_whitespace_only_grammar_treated_as_absent(self):
        self.assertEqual(proxy.build_prompt('', 'p', grammar='   \n  '), 'p')

    def test_load_grammar_reads_file(self):
        import tempfile
        with tempfile.NamedTemporaryFile('w', suffix='.md',
                                         delete=False) as handle:
            handle.write('grammar = "text" ;')
            path = handle.name
        try:
            self.assertEqual(proxy.load_grammar(path), 'grammar = "text" ;')
        finally:
            os.remove(path)

    def test_load_grammar_missing_file_raises(self):
        with self.assertRaises(OSError):
            proxy.load_grammar('/nonexistent/path/to/grammar.md')

    def test_config_defaults_to_no_grammar(self):
        config = proxy.Config()
        self.assertEqual(config.grammar_file, '')
        self.assertEqual(config.grammar_text, '')

    def test_config_loads_grammar_from_explicit_path(self):
        import tempfile
        with tempfile.NamedTemporaryFile('w', suffix='.md',
                                         delete=False) as handle:
            handle.write('from-arg = "x" ;')
            path = handle.name
        try:
            config = proxy.Config(grammar_file=path)
            self.assertEqual(config.grammar_text, 'from-arg = "x" ;')
        finally:
            os.remove(path)

    def test_llm_api_key_defaults_from_environment(self):
        with mock.patch.dict(os.environ, {'LLM_API_KEY': 'from-env'}):
            self.assertEqual(proxy.Config().llm_api_key, 'from-env')

    def test_llm_api_key_defaults_empty_without_environment(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            self.assertEqual(proxy.Config().llm_api_key, '')

    def test_llm_api_key_explicit_arg_overrides_environment(self):
        with mock.patch.dict(os.environ, {'LLM_API_KEY': 'from-env'}):
            config = proxy.Config(llm_api_key='explicit')
            self.assertEqual(config.llm_api_key, 'explicit')


class SanitizeCompletionTests(unittest.TestCase):

    def test_strips_nul_bytes(self):
        self.assertEqual(proxy.sanitize_completion('a\0b'), 'ab')

    def test_default_max_lines_is_thirty(self):
        text = '\n'.join(f'line{i}' for i in range(40))
        expected = '\n'.join(f'line{i}' for i in range(30))
        self.assertEqual(proxy.sanitize_completion(text), expected)

    def test_short_multiline_text_untouched_by_default(self):
        self.assertEqual(proxy.sanitize_completion('a\nb\nc'), 'a\nb\nc')

    def test_preserves_trailing_whitespace_on_single_line(self):
        self.assertEqual(proxy.sanitize_completion(' := 42;   '), ' := 42;   ')

    def test_empty_completion_stays_empty(self):
        self.assertEqual(proxy.sanitize_completion(''), '')

    def test_max_lines_keeps_up_to_that_many_lines(self):
        self.assertEqual(proxy.sanitize_completion('a\nb\nc', max_lines=2),
                         'a\nb')

    def test_max_lines_leaves_shorter_text_untouched(self):
        self.assertEqual(proxy.sanitize_completion('a\nb', max_lines=5),
                         'a\nb')

    def test_max_lines_exact_match_untouched(self):
        self.assertEqual(proxy.sanitize_completion('a\nb\nc', max_lines=3),
                         'a\nb\nc')

    def test_max_lines_below_one_still_keeps_one_line(self):
        self.assertEqual(proxy.sanitize_completion('a\nb', max_lines=0), 'a')


class ExtractCompletionsTests(unittest.TestCase):

    def test_extracts_text_model_and_id(self):
        text, model, request_id = proxy.extract_completions(
            chat_response(' := 42;'))
        self.assertEqual((text, model, request_id),
                         (' := 42;', 'test-model', 'abc123'))

    def test_missing_choices_raises_upstream_error(self):
        with self.assertRaises(proxy.UpstreamError):
            proxy.extract_completions({})

    def test_empty_choices_raises_upstream_error(self):
        with self.assertRaises(proxy.UpstreamError):
            proxy.extract_completions({'choices': []})

    def test_choice_without_message_raises_upstream_error(self):
        with self.assertRaises(proxy.UpstreamError):
            proxy.extract_completions({'choices': [{}]})

    def test_exhausted_reasoning_budget_raises_upstream_error(self):
        # finish_reason "length" + empty content + non-empty
        # reasoning_content: the model spent its whole budget thinking and
        # never answered. This must not be returned as an empty completion.
        response = chat_response('',
                                 finish_reason='length',
                                 reasoning_content='...thinking...')
        with self.assertRaises(proxy.UpstreamError):
            proxy.extract_completions(response)

    def test_empty_content_with_stop_finish_reason_is_a_valid_empty_completion(
            self):
        # Distinguish "model deliberately answered with nothing" (finish
        # reason "stop") from the exhausted-reasoning-budget case above.
        text, _model, _id = proxy.extract_completions(
            chat_response('', finish_reason='stop'))
        self.assertEqual(text, '')

    def test_strips_markdown_code_fence_unconditionally(self):
        # No multi-candidate JSON parsing left to justify fence-stripping
        # only sometimes -- it now runs on every completion, since the
        # minimal system prompt (unlike the old one) doesn't ask the model
        # to avoid markdown, and fences show up often enough to need
        # cleanup regardless.
        response = chat_response('```pascal\n a := 1;\n```')
        text, _model, _id = proxy.extract_completions(response)
        self.assertEqual(text, 'a := 1;')


class PingUpstreamTests(unittest.TestCase):

    def setUp(self):
        self.config = proxy.Config()
        self._orig_call_upstream = proxy.call_upstream
        self.addCleanup(setattr, proxy, 'call_upstream',
                        self._orig_call_upstream)

    def test_returns_text_and_model_on_success(self):
        captured = {}

        def fake_call_upstream(prompt,
                               config,
                               max_tokens=None,
                               temperature=None,
                               system_prompt=None):
            captured['max_tokens'] = max_tokens
            captured['temperature'] = temperature
            return chat_response('ok')

        proxy.call_upstream = fake_call_upstream
        text, model = proxy.ping_upstream(self.config)
        self.assertEqual((text, model), ('ok', 'test-model'))
        # The probe reuses the real configured max_tokens: a smaller fixed
        # budget would report "not responding" on a reasoning backend that
        # needs its full budget just to finish thinking, even though a real
        # /complete request at that same budget succeeds.
        self.assertIsNone(captured['max_tokens'])
        self.assertEqual(captured['temperature'], 0.0)

    def test_propagates_upstream_error(self):

        def boom(prompt,
                 config,
                 max_tokens=None,
                 temperature=None,
                 system_prompt=None):
            raise proxy.UpstreamError('could not reach upstream: refused')

        proxy.call_upstream = boom
        with self.assertRaises(proxy.UpstreamError):
            proxy.ping_upstream(self.config)


class CalibrateReasoningEffortTests(unittest.TestCase):

    def setUp(self):
        self.config = proxy.Config()
        self._orig_call_upstream = proxy.call_upstream
        self.addCleanup(setattr, proxy, 'call_upstream',
                        self._orig_call_upstream)

    def test_picks_the_first_candidate_that_answers(self):
        attempted = []

        def fake_call_upstream(prompt,
                               config,
                               max_tokens=None,
                               temperature=None,
                               reasoning_effort=None,
                               system_prompt=None):
            attempted.append(reasoning_effort)
            if reasoning_effort == 'none':
                raise proxy.ReasoningBudgetExhausted('exhausted')
            return chat_response('ok')  # 'low' (the next candidate) works

        proxy.call_upstream = fake_call_upstream
        result = proxy.calibrate_reasoning_effort(self.config)
        self.assertEqual(result, 'low')
        self.assertEqual(attempted, ['none', 'low'])

    def test_first_candidate_works_tries_only_that_one(self):
        attempted = []

        def fake_call_upstream(prompt,
                               config,
                               max_tokens=None,
                               temperature=None,
                               reasoning_effort=None,
                               system_prompt=None):
            attempted.append(reasoning_effort)
            return chat_response('ok')

        proxy.call_upstream = fake_call_upstream
        result = proxy.calibrate_reasoning_effort(self.config)
        self.assertEqual(result, 'none')
        self.assertEqual(attempted, ['none'])

    def test_falls_back_to_none_when_every_candidate_exhausts_budget(self):

        def fake_call_upstream(prompt,
                               config,
                               max_tokens=None,
                               temperature=None,
                               reasoning_effort=None,
                               system_prompt=None):
            raise proxy.ReasoningBudgetExhausted('exhausted')

        proxy.call_upstream = fake_call_upstream
        result = proxy.calibrate_reasoning_effort(self.config)
        self.assertEqual(result, 'none')

    def test_tries_all_five_candidates_in_order_before_giving_up(self):
        attempted = []

        def fake_call_upstream(prompt,
                               config,
                               max_tokens=None,
                               temperature=None,
                               reasoning_effort=None,
                               system_prompt=None):
            attempted.append(reasoning_effort)
            raise proxy.ReasoningBudgetExhausted('exhausted')

        proxy.call_upstream = fake_call_upstream
        proxy.calibrate_reasoning_effort(self.config)
        self.assertEqual(attempted, ['none', 'low', 'medium', 'high', ''])

    def test_stops_immediately_on_a_non_budget_upstream_error(self):
        # A connectivity/transport failure should not be retried against
        # four more candidates -- that would just multiply the timeout wait
        # for no benefit, since the backend is unreachable regardless of
        # reasoning_effort.
        attempted = []

        def fake_call_upstream(prompt,
                               config,
                               max_tokens=None,
                               temperature=None,
                               reasoning_effort=None,
                               system_prompt=None):
            attempted.append(reasoning_effort)
            raise proxy.UpstreamError('could not reach upstream: refused')

        proxy.call_upstream = fake_call_upstream
        result = proxy.calibrate_reasoning_effort(self.config)
        self.assertEqual(result, 'none')
        self.assertEqual(attempted, ['none'])

    def test_logs_progress_via_the_log_callback(self):
        lines = []

        def fake_call_upstream(prompt,
                               config,
                               max_tokens=None,
                               temperature=None,
                               reasoning_effort=None,
                               system_prompt=None):
            if reasoning_effort == 'none':
                raise proxy.ReasoningBudgetExhausted('exhausted')
            return chat_response('ok')

        proxy.call_upstream = fake_call_upstream
        proxy.calibrate_reasoning_effort(self.config, log=lines.append)
        self.assertTrue(any('none' in line for line in lines))
        self.assertTrue(
            any('low' in line and 'works' in line for line in lines))


class ConfigTests(unittest.TestCase):

    def test_defaults_point_at_local_llama_cpp_no_auth(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            config = proxy.Config()
        self.assertEqual(config.llm_base_url, 'http://127.0.0.1:8080/v1')
        self.assertEqual(config.llm_api_key, '')
        self.assertEqual(config.chat_completions_url,
                         'http://127.0.0.1:8080/v1/chat/completions')
        self.assertEqual(config.host, '127.0.0.1')
        # 'auto': the operator hasn't passed --reasoning-effort, so main()
        # must run calibration against the live backend rather than
        # silently defaulting to a value that could be wrong for whichever
        # model is actually loaded.
        self.assertEqual(config.reasoning_effort, 'auto')

    def test_constructor_args_override_defaults(self):
        config = proxy.Config(
            llm_base_url='http://example.invalid:9999/v1/',
            llm_api_key='secret',
            port=1234,
        )
        self.assertEqual(config.llm_base_url, 'http://example.invalid:9999/v1')
        self.assertEqual(config.llm_api_key, 'secret')
        self.assertEqual(config.port, 1234)

    def test_reasoning_effort_can_be_disabled_for_strict_backends(self):
        config = proxy.Config(reasoning_effort='')
        self.assertEqual(config.reasoning_effort, '')

    def test_system_prompt_defaults_to_bundled_file(self):
        config = proxy.Config()
        self.assertEqual(config.system_prompt, proxy.SYSTEM_PROMPT)

    def test_system_prompt_explicit_arg_overrides_default(self):
        config = proxy.Config(system_prompt='custom system prompt')
        self.assertEqual(config.system_prompt, 'custom system prompt')

    def test_max_lines_defaults_to_thirty(self):
        config = proxy.Config()
        self.assertEqual(config.max_lines, 30)

    def test_max_lines_explicit_arg_overrides_default(self):
        config = proxy.Config(max_lines=10)
        self.assertEqual(config.max_lines, 10)


class PromptFileLoadingTests(unittest.TestCase):

    def test_load_prompt_text_reads_bundled_file(self):
        text = proxy.load_prompt_text('system_prompt.txt')
        self.assertTrue(text)
        self.assertFalse(text.endswith('\n'))

    def test_load_prompt_override_reads_arbitrary_path(self):
        import tempfile
        with tempfile.NamedTemporaryFile('w', suffix='.txt',
                                         delete=False) as handle:
            handle.write('override text\n')
            path = handle.name
        try:
            self.assertEqual(proxy.load_prompt_override(path), 'override text')
        finally:
            os.remove(path)

    def test_load_prompt_override_missing_file_raises(self):
        with self.assertRaises(OSError):
            proxy.load_prompt_override('/nonexistent/path/to/prompt.txt')


class CallUpstreamPayloadTests(unittest.TestCase):
    """Verify the request body call_upstream actually sends, via a fake
    urlopen -- catches regressions in message shape / reasoning_effort
    placement without a live backend."""

    def test_sends_chat_messages_and_top_level_reasoning_effort(self):
        captured = {}

        class FakeResponse:

            def __enter__(self):
                return self

            def __exit__(self, *exc):
                return False

            def read(self):
                return json.dumps(chat_response('ok')).encode('utf-8')

        def fake_urlopen(request, timeout=None):
            captured['url'] = request.full_url
            captured['body'] = json.loads(request.data)
            return FakeResponse()

        config = proxy.Config(reasoning_effort='none')
        orig_urlopen = proxy.urllib.request.urlopen
        proxy.urllib.request.urlopen = fake_urlopen
        try:
            proxy.call_upstream('VAR x', config)
        finally:
            proxy.urllib.request.urlopen = orig_urlopen

        self.assertEqual(captured['url'], config.chat_completions_url)
        body = captured['body']
        self.assertEqual(body['reasoning_effort'], 'none')
        self.assertEqual(body['messages'], [
            {
                'role': 'system',
                'content': proxy.SYSTEM_PROMPT
            },
            {
                'role': 'user',
                'content': 'VAR x'
            },
        ])
        self.assertNotIn('prompt', body)

    def test_never_sends_a_raw_stream_stop_sequence(self):
        # A "stop": ["\n"] here would apply to the raw token stream on at
        # least one observed backend, including reasoning_content -- killing
        # generation mid-thought before any answer is written. Single-line
        # enforcement belongs to sanitize_completion, on the returned
        # content only.
        captured = {}

        class FakeResponse:

            def __enter__(self):
                return self

            def __exit__(self, *exc):
                return False

            def read(self):
                return json.dumps(chat_response('ok')).encode('utf-8')

        def fake_urlopen(request, timeout=None):
            captured['body'] = json.loads(request.data)
            return FakeResponse()

        config = proxy.Config()
        orig_urlopen = proxy.urllib.request.urlopen
        proxy.urllib.request.urlopen = fake_urlopen
        try:
            proxy.call_upstream('VAR x', config)
        finally:
            proxy.urllib.request.urlopen = orig_urlopen

        self.assertNotIn('stop', captured['body'])

    def test_auto_sentinel_is_never_sent_literally_to_the_backend(self):
        # If 'auto' somehow reaches call_upstream uncalibrated (e.g. a
        # caller that builds Config directly and skips main()'s calibration
        # step), it must be treated as "omit the field", never sent upstream
        # as the literal string "auto" -- that is not a valid value for any
        # backend.
        captured = {}

        class FakeResponse:

            def __enter__(self):
                return self

            def __exit__(self, *exc):
                return False

            def read(self):
                return json.dumps(chat_response('ok')).encode('utf-8')

        def fake_urlopen(request, timeout=None):
            captured['body'] = json.loads(request.data)
            return FakeResponse()

        config = proxy.Config()  # reasoning_effort defaults to 'auto'
        orig_urlopen = proxy.urllib.request.urlopen
        proxy.urllib.request.urlopen = fake_urlopen
        try:
            proxy.call_upstream('VAR x', config)
        finally:
            proxy.urllib.request.urlopen = orig_urlopen

        self.assertNotIn('reasoning_effort', captured['body'])

    def test_omits_reasoning_effort_when_configured_empty(self):
        captured = {}

        class FakeResponse:

            def __enter__(self):
                return self

            def __exit__(self, *exc):
                return False

            def read(self):
                return json.dumps(chat_response('ok')).encode('utf-8')

        def fake_urlopen(request, timeout=None):
            captured['body'] = json.loads(request.data)
            return FakeResponse()

        config = proxy.Config(reasoning_effort='')
        orig_urlopen = proxy.urllib.request.urlopen
        proxy.urllib.request.urlopen = fake_urlopen
        try:
            proxy.call_upstream('VAR x', config)
        finally:
            proxy.urllib.request.urlopen = orig_urlopen

        self.assertNotIn('reasoning_effort', captured['body'])


class CallUpstreamErrorHandlingTests(unittest.TestCase):
    """call_upstream against a real, unreachable loopback port -- exercises
    the actual urllib transport-error path without hitting the network."""

    def test_connection_refused_raises_upstream_error(self):
        config = proxy.Config(
            llm_base_url='http://127.0.0.1:1',  # nothing listens here
            upstream_timeout=2,
        )
        with self.assertRaises(proxy.UpstreamError):
            proxy.call_upstream('prompt', config)


class EndToEndTests(unittest.TestCase):
    """Runs the real HTTP handler on an ephemeral loopback port, with
    call_upstream monkeypatched so no network call happens."""

    def setUp(self):
        self.config = proxy.Config(port=0)
        self.server = proxy.make_server(self.config)
        self.addCleanup(self.server.server_close)
        import threading
        self.thread = threading.Thread(target=self.server.serve_forever,
                                       daemon=True)
        self.thread.start()
        self.addCleanup(self.server.shutdown)
        self.port = self.server.server_address[1]
        self._orig_call_upstream = proxy.call_upstream

    def tearDown(self):
        proxy.call_upstream = self._orig_call_upstream

    def _post(self, body_dict):
        conn = http.client.HTTPConnection('127.0.0.1', self.port, timeout=5)
        payload = json.dumps(body_dict).encode('utf-8')
        conn.request('POST',
                     '/complete',
                     body=payload,
                     headers={'Content-Type': 'application/json'})
        response = conn.getresponse()
        status = response.status
        data = json.loads(response.read())
        conn.close()
        return status, data

    def test_successful_completion_round_trip(self):
        proxy.call_upstream = (
            lambda prompt, config, max_tokens=None, system_prompt=None:
            chat_response(' := 42;', model='test-model', request_id='req-1'))
        status, data = self._post({
            'goal': '',
            'buffer': 'x',
            'cursor': {
                'line': 1,
                'column': 2
            },
        })
        self.assertEqual(status, 200)
        self.assertEqual(
            data, {
                'completions': [' := 42;'],
                'model': 'test-model',
                'request_id': 'req-1',
            })

    def test_custom_system_prompts_reach_call_upstream(self):
        # Overriding Config.system_prompt (as --system-prompt-file does)
        # must actually be what reaches call_upstream, not just the bundled
        # default. Echoed back via the "model" field -- the server forks a
        # child process per connection (see ForkingHTTPServer), so a
        # request handler's fake_call_upstream runs in a copy-on-write
        # child; mutating a shared Python list/dict from in there is
        # invisible to this (parent) test process, but "model" really did
        # cross the wire and so is visible in DATA below.
        self.config.system_prompt = 'CUSTOM SINGLE'

        proxy.call_upstream = (
            lambda prompt, config, max_tokens=None, system_prompt=None:
            chat_response(' ok', model=system_prompt))
        status, data = self._post({
            'buffer': 'x',
            'cursor': {
                'line': 1,
                'column': 1
            },
        })
        self.assertEqual(status, 200)
        self.assertEqual(data['model'], 'CUSTOM SINGLE')

    def test_upstream_error_returns_502_and_leaves_body_generic(self):

        def boom(prompt, config, max_tokens=None, system_prompt=None):
            raise proxy.UpstreamError('could not reach upstream: refused')

        proxy.call_upstream = boom
        status, data = self._post({
            'buffer': 'x',
            'cursor': {
                'line': 1,
                'column': 1
            },
        })
        self.assertEqual(status, 502)
        self.assertIn('error', data)

    def test_malformed_json_returns_400(self):
        conn = http.client.HTTPConnection('127.0.0.1', self.port, timeout=5)
        conn.request('POST',
                     '/complete',
                     body=b'{not json',
                     headers={'Content-Type': 'application/json'})
        response = conn.getresponse()
        status = response.status
        response.read()
        conn.close()
        self.assertEqual(status, 400)

    def test_invalid_schema_returns_400(self):
        status, data = self._post({'buffer': 123, 'cursor': {}})
        self.assertEqual(status, 400)
        self.assertIn('error', data)

    def test_unknown_path_returns_404(self):
        conn = http.client.HTTPConnection('127.0.0.1', self.port, timeout=5)
        conn.request('POST', '/nope', body=b'{}')
        response = conn.getresponse()
        status = response.status
        response.read()
        conn.close()
        self.assertEqual(status, 404)

    def test_empty_completion_from_upstream_is_returned_as_empty_string(self):
        proxy.call_upstream = (
            lambda prompt, config, max_tokens=None, system_prompt=None:
            chat_response('', model='', request_id=''))
        status, data = self._post({
            'buffer': 'x',
            'cursor': {
                'line': 1,
                'column': 1
            },
        })
        self.assertEqual(status, 200)
        self.assertEqual(data['completions'], [''])

    def _get(self, path):
        conn = http.client.HTTPConnection('127.0.0.1', self.port, timeout=5)
        conn.request('GET', path)
        response = conn.getresponse()
        status = response.status
        data = json.loads(response.read())
        conn.close()
        return status, data

    def test_health_ok_when_upstream_responds(self):
        proxy.call_upstream = (
            lambda prompt, config, max_tokens=None, temperature=None,
            system_prompt=None: chat_response('pong', model='test-model'))
        status, data = self._get('/health')
        self.assertEqual(status, 200)
        self.assertEqual(data['status'], 'ok')
        self.assertEqual(data['model'], 'test-model')
        self.assertEqual(data['sample_completion'], 'pong')
        self.assertIn('upstream', data)
        # Reflects whatever the server's config currently holds -- in this
        # test harness that's the uncalibrated 'auto' sentinel, since
        # calibration is main()'s job, not make_server()'s.
        self.assertEqual(data['reasoning_effort'], 'auto')

    def test_health_503_when_upstream_unreachable(self):

        def boom(prompt,
                 config,
                 max_tokens=None,
                 temperature=None,
                 system_prompt=None):
            raise proxy.UpstreamError('could not reach upstream: refused')

        proxy.call_upstream = boom
        status, data = self._get('/health')
        self.assertEqual(status, 503)
        self.assertEqual(data['status'], 'error')
        self.assertIn('error', data)

    def test_unknown_get_path_returns_404(self):
        status, _data = self._get('/nope')
        self.assertEqual(status, 404)

    def test_multiline_upstream_text_is_returned_uncut_within_the_cap(self):
        # Multi-line completions are welcome by default now (max_lines=30);
        # only a completion actually longer than the cap gets truncated
        # (see test_completion_longer_than_max_lines_is_truncated).
        proxy.call_upstream = (
            lambda prompt, config, max_tokens=None, system_prompt=None:
            chat_response('first\nsecond'))
        status, data = self._post({
            'buffer': 'x',
            'cursor': {
                'line': 1,
                'column': 1
            },
        })
        self.assertEqual(status, 200)
        self.assertEqual(data['completions'], ['first\nsecond'])

    def test_completion_longer_than_max_lines_is_truncated(self):
        text = '\n'.join(f'line{i}' for i in range(40))
        proxy.call_upstream = (lambda prompt, config, max_tokens=None,
                               system_prompt=None: chat_response(text))
        status, data = self._post({
            'buffer': 'x',
            'cursor': {
                'line': 1,
                'column': 1
            },
        })
        self.assertEqual(status, 200)
        expected = '\n'.join(f'line{i}' for i in range(self.config.max_lines))
        self.assertEqual(data['completions'], [expected])

    def test_concurrent_requests_each_get_independent_responses(self):
        # Exercises the ForkingHTTPServer path itself (every other test here
        # only ever has one request in flight at a time): two overlapping
        # connections must each get back the response that matches what
        # *they* sent, not get crossed or corrupted by running in sibling
        # forked child processes.
        def fake_call_upstream(prompt,
                               config,
                               max_tokens=None,
                               system_prompt=None):
            # Echo the buffer prefix back via "model" so each response can
            # be matched to its own request.
            return chat_response(' ok;', model=prompt)

        proxy.call_upstream = fake_call_upstream
        results = {}

        def post_one(tag):
            results[tag] = self._post({
                'buffer': f'x_{tag}',
                'cursor': {
                    'line': 1,
                    'column': 1 + len(f'x_{tag}')
                },
            })

        import threading
        threads = [
            threading.Thread(target=post_one, args=(tag, ))
            for tag in ('a', 'b', 'c')
        ]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=5)

        for tag in ('a', 'b', 'c'):
            status, data = results[tag]
            self.assertEqual(status, 200)
            self.assertEqual(data['model'], f'x_{tag}')
            self.assertEqual(data['completions'], [' ok;'])


if __name__ == '__main__':
    unittest.main()
