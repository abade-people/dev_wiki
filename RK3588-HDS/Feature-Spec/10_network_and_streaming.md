# 네트워크 및 스트리밍

> **참조 소스**: `src/network/NetworkApp.cc`, `src/network/http/Service.cc`, `src/network/http/ServiceInfo.cc`, `src/network/http/ServiceInspection.cc`, `lib/HttpRequest.cc`, `lib/HttpResponse.cc`

---

## 1. HTTP 서버

### 1.1 서비스 엔드포인트

| 엔드포인트 | 기능 |
|-----------|------|
| `/live` | 라이브 영상 스트리밍 |
| `/search` | 녹화 파일 시간/이벤트 검색 |
| `/playback` | 재생 영상 스트리밍 |
| `/capture` | 스냅샷 촬영 |
| `/osd_capture` | OSD 화면 캡처 |
| `/control` | 시스템 제어 (PTZ, 뷰 모드) |
| `/config` | 설정 조회/변경 |
| `/upgrade` | 펌웨어 업그레이드 |
| `/download` | 녹화 파일 다운로드 |
| `/backup` | 백업 관리 |
| `/syslog` | 시스템 로그 조회 |
| `/debug` | 디버그 페이지 |
| `/gsensor` | G-sensor 데이터 |
| `/gps` | GPS 데이터 |
| `/driving_info` | 주행 정보 |
| `/smart` | AI 기능 |
| `/webserver` | 웹 인터페이스 페이지 |
| `/command` | 시스템 명령 실행 |
| `/index` | 녹화 인덱스 |
| `/npu_update` | NPU 모델 업데이트 |
| `/inspection` | 검사 프로토콜 |
| `/status` | 시스템 상태 |
| `/iphone_view` | 모바일 스트리밍 |
| `/iphone_m3u8` | HLS 재생 목록 |

### 1.2 인증

- **방식**: HTTP Digest 인증
- **Nonce 관리**: `IM_NETWORK_ADD_NONCE`, `IM_NETWORK_CHECK_NONCE`
- **최대 동시 접속**: 16개 호스트
- **접근 권한**: 메뉴, 백업, 재생, 녹화 중지, 시스템, 계정, 디스크, 시간, 카메라 비활성화

### 1.3 웹 설정 자동 생성

`CONFIG_AUTO_GENERATE_WEB_SETUP` 활성 시, 메뉴 설정을 웹 페이지로 자동 생성.

---

## 2. 라이브 스트리밍

### 2.1 스트리밍 방식

```
클라이언트 요청 (/live?ch=0)
    │
    ▼
LiveMonitor: DCI NET 큐에서 스트림 읽기
    │
    ▼
HTTP 청크 전송 (Transfer-Encoding: chunked)
    │
    ▼
H.264/H.265 스트림 → 클라이언트
```

### 2.2 스트리밍 옵션

| 옵션 | 설명 |
|------|------|
| 채널 | 0~15 |
| 스트림 | primary / secondary |
| 오디오 포함 | on/off |
| JPEG 모드 | MJPEG 스트리밍 |

### 2.3 HLS (iPhone 지원)

- M3U8 재생 목록 생성
- 세그먼트 기반 HTTP 스트리밍
- `/iphone_m3u8`, `/iphone_view`

---

## 3. 원격 검색/재생

### 3.1 시간 검색 API

```
GET /search?from=20260407T000000&to=20260407T235959&ch=0&type=event
    → 시간 범위 내 녹화 목록 반환 (JSON)
```

### 3.2 파일 다운로드

```
GET /download?file=2026040700_000001.imf
    → IMF 파일 직접 다운로드
```

### 3.3 재생 스트리밍

```
GET /playback?time=20260407T120000&ch=0
    → IMF에서 스트림 추출 → HTTP 스트리밍
```

---

## 4. 원격 설정

### 4.1 설정 조회

```
GET /config?menu=record_video
    → JSON 형식 설정 반환
```

### 4.2 설정 변경

```
POST /config?menu=record_video
Content-Type: application/json
{ "resolution": "1080P", "fps": 30, "quality": "high" }
    → IPC를 통해 설정 적용 → 공유 메모리 갱신
```

---

## 5. 네트워크 관리

### 5.1 이더넷 설정

| 항목 | 설명 |
|------|------|
| ETH0 | 주 네트워크 인터페이스 |
| ETH1 | 보조 네트워크 인터페이스 |
| IP/서브넷/게이트웨이 | 수동 또는 DHCP |
| DNS | 1차/2차 DNS |
| QoS | 네트워크 QoS 설정 |

### 5.2 DHCP

- DHCP 클라이언트: `IM_DHCP_CLIENT_RESPONSE`
- DHCP 서버: `IPC_SHM_ITEM_DHCPD` (선택)

### 5.3 WiFi

- WiFi 동글 감지: `IM_WIFI_DONGLE_STATUS_CHANGED`
- AP 스캔: `IM_SET_WIFI_SCAN_RESULT`
- 연결 관리: `IM_WIFI_CONTROL`
- AP 정보 저장: AccessPoint 리스트

### 5.4 DDNS

`IM_NETWORK_DDNS_UPDATE`: 동적 DNS 업데이트

### 5.5 포트포워딩

PortForwardManager: UPnP 기반 포트 자동 매핑

---

## 6. WebSocket

WebSocketResponse: 실시간 상태 알림
- 이벤트 발생 시 클라이언트에 즉시 통보
- JSON 형식 메시지

---

## 7. IPC 메시지 요약

| 메시지 | 설명 |
|--------|------|
| IM_SYNC_REPOSITORY_LIST | 저장소 목록 동기화 |
| IM_NETWORK_ADD_NONCE | HTTP 인증 nonce 추가 |
| IM_NETWORK_CHECK_NONCE | nonce 검증 |
| IM_NETWORK_SET_FLAG | 네트워크 플래그 |
| IM_DHCP_CLIENT_RESPONSE | DHCP 응답 |
| IM_NETWORK_DDNS_UPDATE | DDNS 업데이트 |
| IM_WIFI_CONTROL | WiFi 제어 |
| IM_SET_WIFI_SCAN_RESULT | WiFi 스캔 결과 |
