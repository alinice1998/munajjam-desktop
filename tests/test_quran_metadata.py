import ast
from pathlib import Path
import unittest

from quran_metadata import legacy_riwaya, describe_riwayah


class QuranMetadataTest(unittest.TestCase):
    def test_completed_job_response_keeps_its_data_identity(self):
        from fastapi import FastAPI, HTTPException
        tree = ast.parse(Path('munajjam_server.py').read_text(encoding='utf-8'))
        node = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'get_align_job_status')
        scope = {'app': FastAPI(), 'HTTPException': HTTPException, 'JOBS': {
            'job': {'status': 'completed', 'progress': 100, 'message': '',
                    'quran_metadata': {**describe_riwayah('warsh'), 'surah_number': 2},
                    'result': {'data': [{'ayah_number': 1, 'start': 0, 'end': 1}]}}
        }}
        exec(compile(ast.Module(body=[node], type_ignores=[]), 'munajjam_server.py', 'exec'), scope)
        response = scope['get_align_job_status']('job')
        self.assertEqual(response['riwayah'], 'warsh_an_nafi')
        self.assertEqual(response['ayah_numbering_system'], 'madani_last')
        self.assertEqual(response['data'][0]['ayah_number'], 1)

    def test_http_endpoints_accept_canonical_and_legacy_requests(self):
        from fastapi import FastAPI, File, Form, UploadFile, BackgroundTasks, HTTPException
        from fastapi.testclient import TestClient
        from typing import Optional, Literal
        import time
        import os
        app = FastAPI()
        seen = []
        def loader(surah, riwaya):
            seen.append((surah, riwaya))
            return []  # Stop before inference/audio I/O with the normal 400 response.
        scope = dict(locals(), legacy_riwaya=legacy_riwaya, load_quran_surah_text=loader)
        names = {'create_align_job', 'align_audio_async', 'align_audio_endpoint'}
        tree = ast.parse(Path('munajjam_server.py').read_text(encoding='utf-8'))
        nodes = [n for n in tree.body if isinstance(n, ast.AsyncFunctionDef) and n.name in names]
        exec(compile(ast.Module(body=nodes, type_ignores=[]), 'munajjam_server.py', 'exec'), scope)
        client = TestClient(app)
        for endpoint in ['/align/job/2', '/align-async', '/align']:
            for fields, expected in [
                ({'riwayah': 'hafs_an_asim'}, 'hafsh'),
                ({'riwayah': 'warsh_an_nafi'}, 'warsh'),
                ({'riwaya': 'warsh'}, 'warsh'),
                ({'riwaya': 'hafsh'}, 'hafsh'),
                ({'riwaya': 'hafsh', 'riwayah': 'warsh_an_nafi'}, 'warsh'),
            ]:
                response = client.post(endpoint, data={'surah_id': '2', **fields}, files={'audio': ('test.wav', b'test')})
                self.assertEqual(response.status_code, 400, response.text)
                self.assertEqual(seen[-1], (2, expected))
            response = client.post(endpoint, data={'riwayah': 'unknown'}, files={'audio': ('test.wav', b'test')})
            self.assertEqual(response.status_code, 422)

    def test_aliases_use_the_same_bundled_text(self):
        import json
        for canonical, legacy in [('hafs_an_asim', 'hafsh'), ('warsh_an_nafi', 'warsh')]:
            self.assertEqual(legacy_riwaya(canonical), legacy_riwaya(legacy))
            data = json.loads(Path(f'data/quran_{legacy_riwaya(canonical)}.json').read_text(encoding='utf-8-sig'))
            self.assertEqual(len(data), 114)
        with self.assertRaises(ValueError):
            legacy_riwaya('../../outside')

    def test_real_server_loader_accepts_both_code_generations(self):
        # Run the actual loader without importing GPU inference dependencies.
        import os
        import json
        from typing import List
        tree = ast.parse(Path('munajjam_server.py').read_text(encoding='utf-8'))
        function = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'load_quran_surah_text')
        scope = {'os': os, 'json': json, 'List': List, 'DATA_DIR': str(Path('data').resolve()), 'legacy_riwaya': legacy_riwaya}
        exec(compile(ast.Module(body=[function], type_ignores=[]), 'munajjam_server.py', 'exec'), scope)
        load = scope['load_quran_surah_text']
        for canonical, legacy in [('hafs_an_asim', 'hafsh'), ('warsh_an_nafi', 'warsh')]:
            self.assertEqual(load(2, canonical), load(2, legacy))
            self.assertGreater(len(load(2, canonical)), 280)


if __name__ == '__main__':
    unittest.main()
