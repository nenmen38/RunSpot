#!/usr/bin/env python3
"""확정한 운영 정보로 뜀터의 공개 정책 페이지를 빌드합니다."""

import argparse
from html import escape
import json
from pathlib import Path
import re
from string import Template
from urllib.parse import quote, urlencode, urlsplit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config", type=Path)
    parser.add_argument("output", type=Path)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--privacy-html", type=Path)
    mode.add_argument("--account-deletion-only", action="store_true")
    args = parser.parse_args()

    config = json.loads(args.config.read_text(encoding="utf-8"))
    privacy_url = config.get("PRIVACY_POLICY_URL", "")
    deletion_url = config.get("ACCOUNT_DELETION_URL", "")
    email = config.get("SUPPORT_EMAIL", "")
    targets = [(deletion_url, "account-deletion.html")]
    if args.privacy_html:
        targets.append((privacy_url, "privacy.html"))
    for url, filename in targets:
        parsed = urlsplit(url)
        if (
            parsed.scheme != "https"
            or not parsed.hostname
            or parsed.username
            or parsed.query
            or parsed.fragment
            or parsed.path.rsplit("/", 1)[-1] != filename
        ):
            parser.error(f"{filename}의 공개 HTTPS 주소를 설정해 주세요.")
    if not re.fullmatch(r"[A-Za-z0-9._+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", email):
        parser.error("실제 계정 삭제 요청을 받을 SUPPORT_EMAIL을 설정해 주세요.")

    privacy_html = None
    privacy_link = ""
    if args.privacy_html:
        privacy_html = args.privacy_html.read_text(encoding="utf-8")
        if not all(label in privacy_html for label in ("<html", "뜀터", "개인정보처리방침", email)):
            parser.error("뜀터 이름과 운영 문의 이메일을 포함한 최종 개인정보처리방침 HTML이 필요합니다.")
        if re.search(r"초안|\[\s*\]|\[운영자 이름\]|\[YYYY-MM-DD\]", privacy_html):
            parser.error("개인정보처리방침의 초안 표시와 미확정 항목을 채워 주세요.")
        privacy_link = f'<p><a href="{escape(privacy_url, quote=True)}">뜀터 개인정보처리방침</a></p>'

    query = urlencode(
        {
            "subject": "뜀터 계정 삭제 요청",
            "body": "뜀터 계정과 관련 데이터 삭제를 요청합니다.\n가입에 사용한 이메일: ",
        },
        quote_via=quote,
    )
    template = Path(__file__).resolve().parents[1] / "web/legal/account-deletion.html"
    deletion_html = Template(template.read_text(encoding="utf-8")).substitute(
        deletion_mailto=escape(f"mailto:{quote(email, safe='@')}?{query}", quote=True),
        support_email=escape(email),
        privacy_link=privacy_link,
    )

    args.output.mkdir(parents=True, exist_ok=True)
    if privacy_html is not None:
        (args.output / "privacy.html").write_text(privacy_html, encoding="utf-8")
    (args.output / "account-deletion.html").write_text(deletion_html, encoding="utf-8")


if __name__ == "__main__":
    main()
