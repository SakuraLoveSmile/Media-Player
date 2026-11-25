"""Render the update notes of a KaneoPilot pilot release.

KaneoPilot freezes the root task's ``reporter`` and one-sentence ``summary``
into the task manifest (KaneoPilot ``docs/release-contract.md``). A managed
repository must render its GitHub Release body from that frozen data, so the
in-app update dialog says who reported the need and what was solved instead of
shipping an opaque batch id. Without those fields the previous one-line
prerelease text is kept.
"""
import json
import os
import sys

DEFAULT_REPORTER='用户'
REPORTER_LIMIT=80
SUMMARY_LIMIT=200
# Trailing punctuation that would leave the rendered line dangling (a plan
# objective often ends its opening sentence with '：' before a list).
TRAILING=' \t\u3000。．.，,；;、：:'
FALLBACK='KaneoPilot 预发布构建 {version} (build {build_number})，批次 {batch_id}。'


def _line(value,limit):
    """One flattened, length-bounded line from a frozen manifest field."""
    if not isinstance(value,str):
        return ''
    text=' '.join(value.split())
    if len(text)>limit:
        text=text[:limit].rstrip()+'…'
    return text


def root_member(manifest):
    """The frozen root task member carries reporter/summary."""
    root_id=manifest.get('root_task_id')
    for member in manifest.get('members') or []:
        if isinstance(member,dict) and member.get('task_id')==root_id:
            return member
    return {}


def render(manifest):
    """The user-facing update notes body for a pilot release."""
    member=root_member(manifest)
    summary=_line(member.get('summary'),SUMMARY_LIMIT).rstrip(TRAILING)
    if summary:
        reporter=_line(member.get('reporter'),REPORTER_LIMIT) or DEFAULT_REPORTER
        return '【本次更新】\n\n@{0}：{1}\n'.format(reporter,summary)
    return FALLBACK.format(version=_line(manifest.get('version'),40),
        build_number=manifest.get('build_number',''),batch_id=_line(manifest.get('batch_id'),80))+'\n'


def main(argv):
    if len(argv)!=2:
        print('usage: pilot_notes.py <output-path>',file=sys.stderr)
        return 2
    raw=os.environ.get('TASK_MANIFEST_JSON','')
    try:
        manifest=json.loads(raw)
    except ValueError:
        print('::error::task_manifest_json is not valid JSON.',file=sys.stderr)
        return 1
    if not isinstance(manifest,dict):
        print('::error::task_manifest_json must be a JSON object.',file=sys.stderr)
        return 1
    with open(argv[1],'w',encoding='utf-8') as handle:
        handle.write(render(manifest))
    return 0


if __name__=='__main__':
    sys.exit(main(sys.argv))
