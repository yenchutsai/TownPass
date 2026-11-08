> **素材來源**：「看得懂」服務入口圖示 `assets/png/icon_easy_read.png` 改作自 [Icon Reading Wikipedia in the classroom 59.png](https://commons.wikimedia.org/wiki/File:Icon_Reading_Wikipedia_in_the_classroom_59.png)，作者 Wikimedia Foundation, Education team，以 [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) 授權。**有改動**：去除白色背景、改為台北通圖示配色、移除星形裝飾、補成正方形並縮小為 144×144。詳見 [`assets/ATTRIBUTION.md`](assets/ATTRIBUTION.md)。

## 服務搜尋（模糊搜尋）

「服務」頁最上方的搜尋框，讓民眾用自己的語言、自己的說法找到服務，例如「我收到罰單」「musholla」「phòng cầu nguyện」「ห้องละหมาด」，打錯一兩個字母也找得到。全部在手機上計算，不連網、不用 AI 模型。

- 程式：`lib/page/service_search/`（比對邏輯在 `service_search_engine.dart`）
- 索引：`assets/search/search_index.json`
  - `appServices`：App 內建服務的同義詞，key 是 `MyServiceItemId` 的名稱；標題和說明會自動從 `my_service_model.dart` 帶入。
  - `microservice`：移工微服務（TownPass-Services）的頁面，`path` 是該頁的路由（例如 `/information/line`），`keywords` 依語言分組（`zh`、`en`、`id`、`vi`、`th`、`tl`）。
  - **新增頁面或關鍵字只要改這個檔案**。中文以外的關鍵字目前是初稿，請熟悉該語言的人確認。
- 微服務網址：建置時用 `--dart-define=MIGRANT_SERVICE_URL=https://...` 指定，未指定時是 `https://town-pass-services.vercel.app`（隊友部署在 Vercel 的版本）。
- 測試：`fvm flutter test test/service_search`
- **AI 語意搜尋（選用）**：使用者在搜尋頁按「啟用 AI 語意搜尋」後，下載 EmbeddingGemma 2 Text 270M，搜尋結果下方多一區「可能相關」，依意思推薦（例如「my employer hit me」）。
  - 模型揭露：EmbeddingGemma 2 Text 270M（`embeddinggemma-2-text-270m`），LiteRT-LM 格式（`.litertlm`），Apache-2.0，來源 Hugging Face `litert-community/embeddinggemma-2-text-270m-litert-lm`（revision `9be6e8b9`，SHA-256 固定），推論框架 `flutter_edge_ai` + `flutter_edge_ai_litertlm`（MIT）。約 165 MB，只把文字轉成向量、不生成文字，全部在手機上計算。
  - Demo 前可把模型檔放進 App 的 `Documents/preloaded/`，就不必現場下載。
  - 沒有啟用或無法使用時，只顯示關鍵字搜尋的結果。

# What is Town Pass?

Town Pass is an open-source project developed by the Taipei City Government. With the growth of smart cities, the demand for digitalization in city management and citizen services continues to rise. As we enter a new digital era, our goal is to involve citizens in the process, combining third-party expertise and innovation to make digital life in Taipei more convenient.

Town Pass is not just an application; it is an open community project. Through open-source, every citizen can participate in the ideation, development, and optimization of the application. This not only enhances citizen engagement and satisfaction but also leverages collective intelligence to continuously improve the application, making it truly serve the people. Furthermore, we hope that various municipalities can widely adopt the open-source framework of Town Pass, integrate it with their existing municipal service systems, and quickly have their own applications to enhance digital governance.

Open source is a key driver of technological progress and social development. Through open-source, Town Pass will become an ever-evolving platform, attracting developers from all backgrounds to contribute. We welcome experts to submit code, report issues, provide suggestions, and even develop new features and creative ideas, working together to perfect Town Pass as we advance toward a smart city.

# Getting Started

We highly recommend to read through our [document](https://tpe-guideline.web.app/en/docs/) for more detail.

Here are some quick setup guide.

## Requirement

- [Flutter](https://docs.flutter.dev/get-started/install) or [FVM](https://fvm.app/documentation/getting-started/installation)
- [XCode](https://developer.apple.com/xcode/) (for iOS)
- [Android SDK](https://developer.android.com/studio/index.html) (for Android, with or without Android Studio)

## Build the Project

1. Get the packages project needed:

   ``` bash
   flutter pub get
   ```

2. Generate additional needed dart code for the project.

   ``` bash
   dart run build_runner build
   ```

3. You are all set now, Run the project from your IDE or the through the command line:

   ``` bash
   flutter run
   ```
