import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parent))
import pilot_notes


def _manifest(**member):
    return dict(
        schema=1,batch_id='bed49d48-ae0e-4694-ac5f-76d7aed63066',
        root_task_id='vnvdoiz6r6ik8s136gd5bpz2',version='0.4.16',build_number=1795577309,
        members=[dict(task_id='vnvdoiz6r6ik8s136gd5bpz2',head_sha='b'*40,**member)],
    )


class RenderTest(unittest.TestCase):
    def test_renders_reporter_and_solved_problem(self):
        notes=pilot_notes.render(_manifest(reporter='上杉九月',summary='一起看页填写自建服务地址后不再报通用失败'))
        self.assertEqual(notes,'【本次更新】\n\n@上杉九月：一起看页填写自建服务地址后不再报通用失败\n')

    def test_trailing_colon_is_dropped(self):
        summary='用户在“一起看”页填写自建服务地址后，不再出现无信息量的“一起看操作失败，请稍后重试”：'
        notes=pilot_notes.render(_manifest(reporter='上杉九月',summary=summary))
        self.assertEqual(notes,'【本次更新】\n\n@上杉九月：用户在“一起看”页填写自建服务地址后，'
            '不再出现无信息量的“一起看操作失败，请稍后重试”\n')

    def test_missing_reporter_falls_back_to_user(self):
        notes=pilot_notes.render(_manifest(summary='隐藏统计卡片'))
        self.assertEqual(notes,'【本次更新】\n\n@用户：隐藏统计卡片\n')

    def test_missing_summary_keeps_the_previous_prerelease_line(self):
        notes=pilot_notes.render(_manifest(reporter='上杉九月'))
        self.assertEqual(notes,'KaneoPilot 预发布构建 0.4.16 (build 1795577309)，'
            '批次 bed49d48-ae0e-4694-ac5f-76d7aed63066。\n')

    def test_summary_is_flattened_and_bounded(self):
        notes=pilot_notes.render(_manifest(reporter='上杉九月',summary='第一行\n第二行  '+'长'*300))
        line=notes.split('\n\n',1)[1].strip()
        self.assertTrue(line.startswith('@上杉九月：第一行 第二行 '))
        self.assertTrue(line.endswith('…'))
        self.assertLessEqual(len(line),len('@上杉九月：')+pilot_notes.SUMMARY_LIMIT+1)

    def test_cli_writes_the_notes_file(self):
        script=Path(__file__).resolve().parent/'pilot_notes.py'
        with tempfile.TemporaryDirectory() as tmp:
            out=Path(tmp)/'pilot-notes.md'
            env=dict(os.environ,TASK_MANIFEST_JSON=json.dumps(_manifest(reporter='上杉九月',summary='隐藏统计卡片')))
            done=subprocess.run([sys.executable,str(script),str(out)],env=env,capture_output=True,text=True)
            self.assertEqual(done.returncode,0,done.stderr)
            self.assertEqual(out.read_text(encoding='utf-8'),'【本次更新】\n\n@上杉九月：隐藏统计卡片\n')

    def test_cli_rejects_a_broken_manifest(self):
        script=Path(__file__).resolve().parent/'pilot_notes.py'
        with tempfile.TemporaryDirectory() as tmp:
            out=Path(tmp)/'pilot-notes.md'
            env=dict(os.environ,TASK_MANIFEST_JSON='not json')
            done=subprocess.run([sys.executable,str(script),str(out)],env=env,capture_output=True,text=True)
            self.assertEqual(done.returncode,1)
            self.assertIn('not valid JSON',done.stderr)
            self.assertFalse(out.exists())


if __name__=='__main__':
    unittest.main()
