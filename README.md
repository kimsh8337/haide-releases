# Haide

Haide는 macOS용 AI 에이전트 개발 환경(ADE)입니다. 프로젝트마다 Git 워크트리를 만들고, 워크트리마다
Claude Code·Codex 에이전트를 터미널 탭으로 띄워 함께 일합니다.

- 에이전트 상태(실행 중·질문·승인 필요·완료)를 사이드바와 상태바에서 확인하고, 완료·질문은 알림으로 받습니다.
- 에이전트가 바꾼 코드는 VS Code급 편집기·diff·전체 검색으로 확인합니다.
- Claude·Codex 계정 사용량을 상태바에 표시합니다.
- 여러 에이전트에게 일을 나눠 주는 오케스트레이션(`haide` CLI)과 GitHub·Jira 대시보드가 들어 있습니다.
- 앱을 꺼도 터미널과 에이전트는 계속 실행되고, 다시 켜면 그대로 이어집니다.

이 저장소는 설치 파일 배포용입니다. 설치 파일은 [Releases](../../releases)에 있습니다.

## 요구 사항

- macOS 11 이상, **Apple Silicon(M1 이상)**. Intel Mac은 지원하지 않습니다.
- `git`
- 에이전트를 쓰려면 [Claude Code](https://docs.anthropic.com/en/docs/claude-code) 또는 [Codex CLI](https://github.com/openai/codex)가 설치·로그인돼 있어야 합니다.
- 선택: GitHub 대시보드는 로그인된 [`gh`](https://cli.github.com/), Jira 대시보드는 Jira API 토큰이 필요합니다.

## 설치

1. [Releases](../../releases/latest)에서 `Haide-<버전>-arm64.dmg`를 받습니다.
2. DMG를 열고 **Haide**를 **응용 프로그램(Applications)** 폴더로 끌어 놓습니다.
3. 처음 실행할 때 아래 '처음 열 때 경고'를 따릅니다.

### 처음 열 때 경고

Haide는 아직 Apple 개발자 서명·공증을 받지 않았습니다. 그래서 처음 열면 macOS가
"Apple은 'Haide'에 악성 코드가 없음을 확인할 수 없습니다" 같은 경고를 띄우고 실행을 막습니다.

**방법 1 — 시스템 설정에서 허용**

1. Haide를 한 번 실행해 경고가 뜨면 **완료**를 누릅니다.
2. **시스템 설정 → 개인정보 보호 및 보안**에서 아래쪽 'Haide' 항목의 **그래도 열기**를 누릅니다.
3. 암호 또는 Touch ID로 확인한 뒤 다시 **열기**를 누릅니다.

**방법 2 — 터미널에서 격리 표시 지우기**

```sh
xattr -dr com.apple.quarantine /Applications/Haide.app
```

한 번 허용하면 다음부터는 그냥 열립니다. 새 버전을 설치하면 다시 허용해야 할 수 있습니다.

### 처음 실행 후 뜨는 권한 창

- **폴더 접근**(데스크탑·문서·다운로드): 그 폴더 안의 프로젝트를 열 때 묻습니다. 허용해야 파일·Git 상태·검색이 동작합니다.
- **키체인 접근**: Claude 계정 사용량을 표시하려고 Claude Code 로그인 정보를 읽을 때 묻습니다. **항상 허용**을 누르면 다시 묻지 않습니다. 거부해도 다른 기능은 그대로 쓸 수 있습니다.
- **알림**: 에이전트 완료·질문 알림을 받으려면 허용합니다.

## 업데이트

아직 자동 업데이트가 없습니다. [Releases](../../releases)에서 새 버전 DMG를 받아 같은 방법으로 덮어 설치합니다.
덮어 설치하기 전에 Haide를 종료(⌘Q)하세요. 실행 중인 에이전트 세션은 유지됩니다.

## 데이터와 삭제

- 설정과 기록은 `~/.haide` 폴더에 저장됩니다.
- 지우려면 **Haide 메뉴 → Haide 종료 및 모든 세션 종료**로 끈 뒤 `/Applications/Haide.app`을 휴지통에 버립니다.
  설정까지 지우려면 `~/.haide` 폴더도 지웁니다.

## 문제 신고

이 저장소의 [Issues](../../issues)에 macOS 버전, Haide 버전(Haide 메뉴 → Haide에 관하여), 증상을 적어 주세요.
