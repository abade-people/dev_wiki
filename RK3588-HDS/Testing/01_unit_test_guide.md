# HDS App 유닛 테스트 가이드 (Phase 1 + Phase 2)

호스트 x86_64에서 1초 이내 회귀 검증을 가능하게 하는 GoogleTest 기반 유닛 테스트 인프라.

---

## 1. 개요

| 항목 | 값 |
|---|---|
| **프레임워크** | GoogleTest 1.14 + GoogleMock (FetchContent로 자동 다운로드) |
| **빌드 환경** | 호스트 x86_64 (`g++` 13+ / `cmake` 3.16+) — Yocto SDK 불필요 |
| **활성화** | CMake 옵션 `-DBUILD_TESTING=ON` (기본값 OFF, 기존 크로스 빌드 무영향) |
| **HAL 모드** | `BUILD_TESTING=ON` 시 `HAL_PLATFORM=host`로 자동 stub 빌드 → Rockchip 라이브러리 의존성 우회 |
| **테스트 범위** | Phase 1: HW 비의존 6개 모듈(85 케이스) + Phase 2: HAL Mock 의존 5개 모듈 |

---

## 2. 빠른 시작

```bash
cd /media/ksw/dev/new_dev/rk3588/app

# 1) 구성 (최초 1회 — GoogleTest 다운로드 약 30초)
cmake -B build-test -DBUILD_TESTING=ON -DCMAKE_BUILD_TYPE=Debug

# 2) 빌드
cmake --build build-test -j$(nproc)

# 3) 실행
ctest --test-dir build-test --output-on-failure
```

성공 시 출력:
```
100% tests passed, 0 tests failed out of 85
Total Test time (real) =   0.37 sec
```

---

## 3. 빌드 명령어

### 3.1 옵션 조합

| 명령 | 결과 |
|---|---|
| `cmake -B build` | 기존 크로스 빌드 (BUILD_TESTING=OFF, HAL_PLATFORM=rk3588) |
| `cmake -B build-test -DBUILD_TESTING=ON` | 호스트 테스트 빌드 (HAL_PLATFORM=host stub) |
| `cmake -B build-test -DBUILD_TESTING=ON -DCMAKE_BUILD_TYPE=Debug` | 디버그 빌드 (권장: 어설션 + 심볼) |
| `cmake -B build-test -DBUILD_TESTING=ON -DCMAKE_BUILD_TYPE=Release` | 최적화 빌드 (성능 회귀 확인용) |

### 3.2 빌드 타깃

```bash
# 전체 (모든 라이브러리 + 모든 테스트)
cmake --build build-test -j$(nproc)

# 특정 모듈만 빌드
cmake --build build-test --target test_hds_ipc -j$(nproc)
cmake --build build-test --target test_hds_media -j$(nproc)

# GoogleTest만 미리 받아두기
cmake --build build-test --target gtest_main -j$(nproc)
```

### 3.3 클린 빌드

```bash
# 빌드 디렉토리 통째로 제거
rm -rf build-test
cmake -B build-test -DBUILD_TESTING=ON
cmake --build build-test -j$(nproc)
```

> **참고**: `BUILD_TESTING=ON` 시 `hds_recorder_app` 등 9개 실행 파일은 `EXCLUDE_FROM_ALL`로 빌드 대상에서 제외된다. Stub HAL이 `HalFactory::Create*()` 함수를 제공하지 않아 링크가 실패하기 때문. 라이브러리(`libhds_*.a`)만 빌드된다.

---

## 4. 테스트 실행

### 4.1 ctest

```bash
# 전체 (실패 시 로그 출력)
ctest --test-dir build-test --output-on-failure

# 특정 모듈 (정규식 필터)
ctest --test-dir build-test -R hds_ipc
ctest --test-dir build-test -R MessageBus
ctest --test-dir build-test -R "Gps|Gsensor"

# 상세 출력 (개별 케이스 로그)
ctest --test-dir build-test -V

# 등록된 테스트 목록만 확인
ctest --test-dir build-test -N

# 병렬 실행 (이미 빠르지만 더 빠르게)
ctest --test-dir build-test -j$(nproc)

# 실패한 테스트만 재실행
ctest --test-dir build-test --rerun-failed --output-on-failure
```

### 4.2 GTest 바이너리 직접 실행

```bash
# 특정 모듈 모든 케이스
./build-test/tests/ipc/test_hds_ipc

# 케이스 필터 (GTest 와일드카드)
./build-test/tests/ipc/test_hds_ipc --gtest_filter="MessageBusTest.*"
./build-test/tests/ipc/test_hds_ipc --gtest_filter="*Concurrent*"

# 케이스 목록만
./build-test/tests/media/test_hds_media --gtest_list_tests

# 첫 실패에서 멈춤
./build-test/tests/ipc/test_hds_ipc --gtest_break_on_failure

# 순서 셔플 (테스트 간 의존성 확인)
./build-test/tests/ipc/test_hds_ipc --gtest_shuffle --gtest_random_seed=12345

# XML 결과 출력 (CI 연동용)
./build-test/tests/ipc/test_hds_ipc --gtest_output=xml:results.xml
```

---

## 5. 디렉토리 구조

```
app/
├── CMakeLists.txt              # BUILD_TESTING 옵션 + add_subdirectory(tests)
├── cmake/
│   └── GoogleTest.cmake        # FetchContent로 v1.14.0 가져옴
├── include/hds/                # 프로덕션 헤더 (변경 없음)
├── src/                        # 프로덕션 소스 (변경 없음)
└── tests/
    ├── CMakeLists.txt          # 모듈별 add_subdirectory
    ├── ipc/
    │   ├── CMakeLists.txt
    │   ├── test_message_bus.cpp
    │   └── test_shared_state.cpp
    ├── ioman/
    │   ├── CMakeLists.txt
    │   ├── test_gps_handler.cpp
    │   ├── test_gsensor_handler.cpp
    │   └── test_can_handler.cpp
    ├── ota/
    │   ├── CMakeLists.txt
    │   └── test_verifier.cpp
    ├── fms/
    │   ├── CMakeLists.txt
    │   └── test_fms_protocol.cpp
    ├── ai/
    │   ├── CMakeLists.txt
    │   ├── test_post_processor.cpp
    │   └── test_detection_pipeline.cpp     # Phase 2
    ├── media/
    │   ├── CMakeLists.txt
    │   └── test_imf_roundtrip.cpp
    ├── mocks/                              # Phase 2: HAL 목 인프라
    │   ├── hal_mocks.h                     # 10개 HAL 인터페이스 목
    │   ├── mock_registry.h                 # MockHalRegistry
    │   └── hal_factory_test.cpp            # 테스트용 HalFactory (→ hds_test_hal_factory)
    ├── recorder/                           # Phase 2
    │   ├── CMakeLists.txt
    │   └── test_channel_pipeline.cpp
    ├── display/                            # Phase 2
    │   ├── CMakeLists.txt
    │   └── test_display_manager.cpp
    └── playback/                           # Phase 2
        ├── CMakeLists.txt
        └── test_playback_engine.cpp
```

---

## 6. 모듈별 테스트 범위

| 모듈 | 케이스 수 | 주요 검증 항목 |
|---|---|---|
| **hds_ipc** | 21 | MessageBus pub/sub, unicast, request/response, 동시성 8스레드 / SharedState reader-writer lock |
| **hds_ioman** | 26 | NMEA 0183 RMC/GGA 파싱 + 체크섬 / G-sensor 합성 가속도 + 중력 보상 / OBD2 PID enum |
| **hds_ota** | 9 | SHA-256 FIPS 180-4 벡터 4종 / 스트리밍 vs one-shot 일치 / Verifier 해시 일치/불일치 |
| **hds_fms** | 16 | 토픽 빌더 / JSON 직렬화 4종 / `JsonExtractString`/`JsonExtractNumber` / `ParseCommand` |
| **hds_ai** | 7 | `BoundingBox` Center/Area / `PostProcessor` Config 라운드트립 / 빈 텐서 safe-fail |
| **hds_media** | 6 | IMF Writer→Reader 라운드트립 / 헤더/채널/플래그 보존 / 청크 타입 분류 |

---

## 6-2. Phase 2 — HAL Mock 의존 모듈

Phase 2는 HAL 인터페이스 의존도가 큰 5개 모듈을 GoogleMock으로 검증한다.
`hal_types.h`의 HalResult/HalFrameBuffer 등을 그대로 사용하여 실제 하드웨어 없이
HAL 호출 순서·인자·반환값 처리·생명주기를 단언한다.

### 6-2.1 목(Mock) 인프라 (`tests/mocks/`)

| 파일 | 역할 |
|---|---|
| `hal_mocks.h` | 10개 HAL 인터페이스(`I*`)에 대한 GoogleMock 목 클래스 (`hds::test::Mock*`) |
| `mock_registry.h` | `MockHalRegistry` — HalFactory가 반환할 목을 보관/인출하는 전역 레지스트리 |
| `hal_factory_test.cpp` | 테스트용 `HalFactory::Create*()` 구현 (레지스트리에서 목을 꺼내 반환) → 정적 라이브러리 `hds_test_hal_factory` |

### 6-2.2 두 가지 HAL 주입 방식

| 방식 | 모듈 | 테스트 주입 방법 |
|---|---|---|
| **생성자 주입** | DetectionPipeline, ChannelPipeline | 목 인스턴스를 생성자 인자로 직접 전달 (`hds_test_hal_factory` 불필요) |
| **HalFactory 내부 생성** | DisplayManager, Ioman, PlaybackEngine | `MockHalRegistry::Install*()`로 목 등록 → 프로덕션 코드의 `HalFactory::Create*()`가 그 목을 반환 |

`HAL_PLATFORM=host`에서 `hds_hal`은 스텁이라 `HalFactory::Create*()` 심볼이 없다.
`hds_test_hal_factory`가 그 심볼을 제공하므로, 팩토리 기반 모듈 테스트는 이 라이브러리를 링크한다.
**프로덕션 코드는 수정하지 않았다** — HAL은 이미 순수 가상 인터페이스 + 의존성 주입/팩토리 구조였다.

### 6-2.3 모듈별 테스트 범위

| 테스트 타깃 | 모듈 | 케이스 | 주요 검증 항목 |
|---|---|---|---|
| `test_hds_ai` (확장) | DetectionPipeline | 6 | Initialize(Open+GetModelInfo) / Open 실패 / ModelInfo 실패는 비치명적 / Start 가드 / 전체 파이프라인(Resize→Convert→SetInput→Run→GetOutput) |
| `test_hds_recorder` | ChannelPipeline | 6 | main/sub 인코더+프로듀서 생성 / Open 실패 / 인코더 실패 롤백 / 듀얼 인코딩 REC·NET 큐 분배 / SetBitrate 전달 / ForceKeyFrame 가드 |
| `test_hds_display` | DisplayManager | 5 | 연결 시 Init→CheckHotplug→SetMode / Init 실패 / 미연결 시 SetMode 생략 / SetLayout 반영 / 렌더링 Start·Stop이 VideoInput 구동 |
| `test_hds_ioman_manager` | Ioman | 7 | GPIO 획득 / 핀 방향별 Export + 이벤트 콜백 / SetAlarmOutput Write(Active-High/Low 반전) / 입력핀·범위초과 거부 / MCU 없는 LED·Buzzer |
| `test_hds_playback` | PlaybackEngine | 5 | HAL 생성+Display Init/SetMode / 디코더 누락 실패 / Display Init 실패 / 오디오 선택성 / 미초기화 SetVolume |

### 6-2.4 목 주입 패턴 예시 (생성자 주입)

```cpp
NiceMock<hds::test::MockVideoInput> vin;
NiceMock<hds::test::MockNpu>        npu;
EXPECT_CALL(vin, Open(_)).WillOnce(Return(HalResult::kSuccess));
EXPECT_CALL(npu, GetModelInfo(42, _)).WillOnce(Return(HalResult::kSuccess));

hds::ai::DetectionPipeline pipe(ch_cfg, model_cfg, pp_cfg, &vin, &ip, &npu, 42);
EXPECT_TRUE(pipe.Initialize());
```

### 6-2.5 목 주입 패턴 예시 (HalFactory 기반)

```cpp
hds::test::MockHalRegistry::Reset();
auto gpio = std::make_unique<NiceMock<hds::test::MockGpio>>();
auto* gpio_raw = gpio.get();
hds::test::MockHalRegistry::InstallGpio(std::move(gpio));  // 소유권 이전

EXPECT_CALL(*gpio_raw, Write(100, 1)).WillOnce(Return(HalResult::kSuccess));

hds::ioman::Ioman ioman(cfg);
ASSERT_TRUE(ioman.Initialize());            // 내부 HalFactory::CreateGpio()가 목 반환
EXPECT_TRUE(ioman.SetAlarmOutput(0, 1));
```

> 스레드를 띄우는 파이프라인(DetectionPipeline/ChannelPipeline/DisplayManager)은
> `GetFrame`이 첫 호출만 유효 프레임, 이후 `kErrorTimeout`을 반환하도록 설정하여
> 한 프레임만 결정론적으로 처리한 뒤 `Stop()`으로 종료한다.

---

## 7. 새 테스트 모듈 추가하기

### 7.1 디렉토리 생성

```bash
mkdir -p app/tests/<module>
```

### 7.2 CMakeLists.txt 작성

`app/tests/<module>/CMakeLists.txt`:

```cmake
add_executable(test_hds_<module>
    test_<file1>.cpp
    test_<file2>.cpp
)

target_link_libraries(test_hds_<module>
    PRIVATE
        hds_<module>          # 기존 정적 라이브러리
        GTest::gtest_main
        GTest::gmock          # Mock 필요 시
        Threads::Threads
)

target_compile_options(test_hds_<module> PRIVATE -Wall -Wextra)

gtest_discover_tests(test_hds_<module>)
```

### 7.3 상위 등록

`app/tests/CMakeLists.txt`에 `add_subdirectory(<module>)` 추가.

### 7.4 테스트 파일 작성 패턴

```cpp
#include "hds/<module>/<header>.h"
#include <gtest/gtest.h>

using namespace hds::<module>;

namespace {

TEST(MyComponentTest, BasicCase) {
    // Arrange
    MyComponent c(default_config);

    // Act
    auto result = c.DoSomething();

    // Assert
    EXPECT_EQ(result.status, ExpectedStatus::kOk);
    EXPECT_NEAR(result.value, 3.14, 0.001);
}

class MyFixtureTest : public ::testing::Test {
protected:
    void SetUp() override { /* per-test setup */ }
    void TearDown() override { /* per-test cleanup */ }
};

TEST_F(MyFixtureTest, UsesFixture) {
    // ...
}

}  // namespace
```

### 7.5 재구성 + 실행

```bash
cmake -B build-test -S . -DBUILD_TESTING=ON       # CMakeLists 변경 후 재구성
cmake --build build-test --target test_hds_<module> -j$(nproc)
./build-test/tests/<module>/test_hds_<module>
```

---

## 8. 자주 쓰는 어설션 (cheatsheet)

```cpp
// 동등성
EXPECT_EQ(actual, expected);              // ==
EXPECT_NE(actual, expected);              // !=
EXPECT_LT(a, b); EXPECT_LE(a, b);         // <, <=
EXPECT_GT(a, b); EXPECT_GE(a, b);         // >, >=

// 부동소수
EXPECT_FLOAT_EQ(a, b);                    // float, 4 ULP 허용
EXPECT_DOUBLE_EQ(a, b);                   // double, 4 ULP 허용
EXPECT_NEAR(actual, expected, abs_error); // 절대 오차

// 불리언
EXPECT_TRUE(cond);
EXPECT_FALSE(cond);

// 문자열
EXPECT_STREQ(a, b);                       // const char* 동등
EXPECT_STRCASEEQ(a, b);                   // 대소문자 무시

// 즉시 종료 (실패 시 다음 어설션 건너뜀)
ASSERT_TRUE(ptr != nullptr);              // 이후 EXPECT_*은 ptr 안전 가정 가능

// 예외
EXPECT_THROW(stmt, ExceptionType);
EXPECT_NO_THROW(stmt);

// 사용자 메시지
EXPECT_EQ(a, b) << "context: " << ctx;
```

---

## 9. 알려진 제약 / Phase 2 예정

### 9.1 Phase 1에서 테스트하지 않은 영역

| 영역 | 이유 | Phase 2 대응 |
|---|---|---|
| **HAL 의존 5개 모듈** (DetectionPipeline, ChannelPipeline, DisplayManager, Ioman, PlaybackEngine) | `IVideoInput*` 등 HAL 인터페이스를 생성자로 주입받음 | GoogleMock으로 `IVideoInput` 등 Mock 구현 |
| **AI Tracker** (SortTracker / HdsTracker) | 헤더 미확인 + 추적 알고리즘 검증 인프라 부재 | 트래커 헤더 공개 + 합성 시퀀스로 검증 |
| **MQTT 패킷 인코더** (`BuildConnectPacket` 등) | `MqttClient`의 private 멤버 함수 | `friend class MqttClientTest` 추가 또는 internal 헤더 분리 |
| **AI `ComputeIou`/`ApplyNms`** | `PostProcessor`의 private static | 동일 (friend 또는 public 노출) |
| **통합 시나리오** (hds_monitor, hds_network, OtaManager) | 프로세스 라이프사이클 + epoll + fw_setenv 시스템 호출 | Phase 3 통합 테스트 (별도 트랙) |

### 9.2 싱글턴 상태 누적

`MessageBus::GetInstance()`, `SharedState::GetInstance()`는 싱글턴이라 테스트 간 상태가 누적된다. 대응:
- 통계는 절대값 대신 **delta**로 비교 (`before/after` 스냅샷)
- `SetUp()`에서 `Stop()` → `Start()`로 디스패치 스레드 재시작
- `SharedState` 업데이트 시 `notify=false`로 MessageBus 깨우지 않기

### 9.3 호스트와 타깃의 ABI 차이

호스트 x86_64에서 통과해도 aarch64에서 동일하다는 보장은 없다. ABI 의존 코드(엔디안, 정렬, 부동소수 정밀도)는 별도로 실기 또는 QEMU 검증 필요.

---

## 10. 트러블슈팅

### 10.1 `No tests were found!!!`
ctest를 잘못된 디렉토리에서 호출. `--test-dir build-test` 명시:
```bash
ctest --test-dir /media/ksw/dev/new_dev/rk3588/app/build-test --output-on-failure
```

### 10.2 GoogleTest 다운로드 실패 (네트워크 없음)
프록시 환경 변수 확인 또는 `FETCHCONTENT_BASE_DIR`로 오프라인 캐시 지정:
```bash
cmake -B build-test -DBUILD_TESTING=ON \
      -DFETCHCONTENT_BASE_DIR=/path/to/cached/_deps
```

### 10.3 `undefined reference to hds::hal::HalFactory::CreateGpio()`
`BUILD_TESTING=OFF`로 빌드 중인데 `HAL_PLATFORM=host`로 설정됨. 명시적으로:
```bash
cmake -B build -DBUILD_TESTING=OFF -DHAL_PLATFORM=rk3588
```
(보통 Yocto SDK 환경 변수 설정 후 크로스 빌드해야 한다.)

### 10.4 무한 재귀 에러 (`cmake/GoogleTest.cmake:34 (include)` 반복)
`list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")`가 추가되면 자체 `GoogleTest.cmake`가 표준 `include(GoogleTest)`와 충돌. **이 줄을 추가하지 말 것**. 현재 구현은 `include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/GoogleTest.cmake")` 형태로 직접 경로 지정.

### 10.5 동시성 테스트 간헐적 실패
`MessageBusTest.ConcurrentPublishersAllDelivered` 같은 동시성 테스트는 디스패치 스레드가 큐를 비울 시간이 필요. `WaitForDispatch(std::chrono::seconds(2))`로 타임아웃 충분히 확보. 머신 부하 시 더 늘려야 할 수 있다.

---

## 11. CI 연동 (향후)

GitHub Actions / Jenkins 등에서 다음 한 줄로 통합 가능:

```yaml
- name: Run HDS unit tests
  run: |
    cd app
    cmake -B build-test -DBUILD_TESTING=ON -DCMAKE_BUILD_TYPE=Debug
    cmake --build build-test -j$(nproc)
    ctest --test-dir build-test --output-on-failure
```

XML 리포트는 `gtest_discover_tests`가 자동 생성하므로 별도 변환 불필요.

---

## 12. 참고

- 도입 계획: `~/.claude/plans/joyful-snacking-lerdorf.md`
- 기능 사양: `MarkDown/feature_spec/`
- Yocto 빌드: `MarkDown/yocto-build/`
- GoogleTest 공식 문서: https://google.github.io/googletest/
