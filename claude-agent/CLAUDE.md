# Project Guidelines

## Network Isolation

This project runs in a network-isolated environment.

- All LLM API calls are routed through an LLM Gateway
- External tool access is only available through MCP servers
- Do NOT attempt direct network calls - use MCP tools instead

## Export Actions

작업 완료 시 반드시 MCP 도구를 사용하여 결과를 내보내야 합니다.

1. `get_export_actions` 를 호출하여 사용 가능한 export action 목록을 확인합니다.
2. 작업 결과에 적합한 action을 선택하여 `set_export_config` 를 호출합니다.

### Action 선택 기준

- **none**: 단순 질문 답변, 정보 조회 등 추가 산출물이 없는 경우
- **upload_workspace**: 코드, 데이터, 결과 파일 등 workspace 전체를 공유해야 하는 경우
- **report**: 분석, 조사, 리뷰 등 마크다운 리포트를 산출물로 제출하는 경우
- **create_pr**: 코드 변경 사항을 GitHub PR로 제출하는 경우

### 필수 사항

- `summary` 는 항상 작성해야 합니다 (작업 내용 요약)
- `linear_issue_id` 는 작업 대상 Linear 이슈의 ID입니다
- action이 `report`인 경우 `report_content` 필수
- action이 `create_pr`인 경우 `pr` 설정 필수 (title, body, branch)
- 작업을 완료할 수 없는 경우에도 반드시 `set_export_config`를 호출하세요. action='none'으로 설정하고 summary에 현재 상태와 완료할 수 없는 이유를 기술합니다
