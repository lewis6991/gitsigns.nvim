# Changelog

## [2.0.0](https://github.com/lewis6991/gitsigns.nvim/compare/v1.0.2...v2.0.0) (2026-01-01)


### ⚠ BREAKING CHANGES

* **config:** remove support for custom highlight names
* **setup:** make optional
* target Nvim 0.11, drop testing for 0.9.5

### Features

* **actions.blame:** add `BlameOpts` parameter ([30ec2bb](https://github.com/lewis6991/gitsigns.nvim/commit/30ec2bbb121fb7b582deba5e5ea3e7486605c25f))
* **actions:** add show_commit ([6e3ee68](https://github.com/lewis6991/gitsigns.nvim/commit/6e3ee68bc9f65b21a21582a3d80e270c7e4f2992))
* add basic gh integration ([aa49c96](https://github.com/lewis6991/gitsigns.nvim/commit/aa49c9675433d3751b7afd198c9f5d2e03252af1)), closes [#839](https://github.com/lewis6991/gitsigns.nvim/issues/839)
* add diffthis options ([93f882f](https://github.com/lewis6991/gitsigns.nvim/commit/93f882f7041a2e779addbd34943812ca66edef5a)), closes [#1314](https://github.com/lewis6991/gitsigns.nvim/issues/1314)
* **blame:** do not show hunk if it was added in commit ([0ddad02](https://github.com/lewis6991/gitsigns.nvim/commit/0ddad02a2ed5249d7d21e90bd550eb8a2f6e7b8c))
* **blame:** general improvements ([7bf01f0](https://github.com/lewis6991/gitsigns.nvim/commit/7bf01f0c27040ffe4ab2d9ed52ab1f926b0670a8))
* **cache:** add support for fetching line ranges ([#1414](https://github.com/lewis6991/gitsigns.nvim/issues/1414)) ([5813e48](https://github.com/lewis6991/gitsigns.nvim/commit/5813e4878748805f1518cee7abb50fd7205a3a48))
* **config:** remove support for custom highlight names ([74fce28](https://github.com/lewis6991/gitsigns.nvim/commit/74fce28b8954c26f79b83736f34093d341bf1a0e))
* **diffthis:** add some rename detection ([8dec8da](https://github.com/lewis6991/gitsigns.nvim/commit/8dec8da8ed8a4463cc6abcd3cc3801373600767d))
* enable new sign calc ([40e235f](https://github.com/lewis6991/gitsigns.nvim/commit/40e235fa320e6f70293ed0274986dfd706bd9142))
* enhance status formatting with color codes ([e9cfaa0](https://github.com/lewis6991/gitsigns.nvim/commit/e9cfaa08c67f80fbca1e6230bf32455beb249523))
* minor improvements to logging ([d62e3ee](https://github.com/lewis6991/gitsigns.nvim/commit/d62e3ee6c35585a3e2aa74581bb2f5adc81db750))
* move watchers to repo objects ([2bf0f73](https://github.com/lewis6991/gitsigns.nvim/commit/2bf0f734f1eeae0ce0839dd93104641ea90082fd))
* overhaul repo watcher ([a772850](https://github.com/lewis6991/gitsigns.nvim/commit/a7728509c034367f99a78e72231155d0f2600ddd))
* remove border from preview_config default ([9a75d9f](https://github.com/lewis6991/gitsigns.nvim/commit/9a75d9f46cfa2128fabf64a625c7901564236f22)), closes [#1241](https://github.com/lewis6991/gitsigns.nvim/issues/1241)
* set buffer name for blame window ([588264b](https://github.com/lewis6991/gitsigns.nvim/commit/588264bee92993df92535b6742576f5655c91b1c))
* **setqflist:** improve text in list ([b014331](https://github.com/lewis6991/gitsigns.nvim/commit/b01433169be710d6c69f7b4ee264d9670698b831))
* **setup:** make optional ([6933bee](https://github.com/lewis6991/gitsigns.nvim/commit/6933beee338960b980b71372e948b6af501445c0)), closes [#1222](https://github.com/lewis6991/gitsigns.nvim/issues/1222)
* **show:** add navigation mappings ([1ee5c1f](https://github.com/lewis6991/gitsigns.nvim/commit/1ee5c1fd068c81f9dd06483e639c2aa4587dc197))
* **show:** adjust output to include tree and parent ([9dfa82c](https://github.com/lewis6991/gitsigns.nvim/commit/9dfa82c1c6e1fe0bc59a719d4bc7ef3a28d9cdc7))
* support for statuscolumn ([b2094c6](https://github.com/lewis6991/gitsigns.nvim/commit/b2094c6b8d72568eca08f18e7e494aa3e22d9963))
* **win_width:** accept winid param ([ace6c6c](https://github.com/lewis6991/gitsigns.nvim/commit/ace6c6c2d045fe951c397a367124638a97f2b60f))


### Bug Fixes

* [#1246](https://github.com/lewis6991/gitsigns.nvim/issues/1246) ([17ab794](https://github.com/lewis6991/gitsigns.nvim/commit/17ab794b6fce6fce768430ebc925347e349e1d60))
* [#1274](https://github.com/lewis6991/gitsigns.nvim/issues/1274) ([550757c](https://github.com/lewis6991/gitsigns.nvim/commit/550757c41a25b80447b821ca3b9ac1cfda894267))
* [#1277](https://github.com/lewis6991/gitsigns.nvim/issues/1277) ([c5a39b2](https://github.com/lewis6991/gitsigns.nvim/commit/c5a39b2cf7fa41a364fa82a6bb08f6c6091cc6b2))
* [#1280](https://github.com/lewis6991/gitsigns.nvim/issues/1280) ([4e1337a](https://github.com/lewis6991/gitsigns.nvim/commit/4e1337abe78000c14317a2707f0fd713572a967d))
* [#1300](https://github.com/lewis6991/gitsigns.nvim/issues/1300) ([7ce11ab](https://github.com/lewis6991/gitsigns.nvim/commit/7ce11abbb8b038a9de4fb6f75d8289c58d81aed7))
* [#1307](https://github.com/lewis6991/gitsigns.nvim/issues/1307) ([ab9e05d](https://github.com/lewis6991/gitsigns.nvim/commit/ab9e05d1cd5b372d4d443fa5c8e0e334232f2c77))
* [#1312](https://github.com/lewis6991/gitsigns.nvim/issues/1312) ([5624b5e](https://github.com/lewis6991/gitsigns.nvim/commit/5624b5ebe6988c75d3f4eb588b9f31f3847a721c))
* [#1372](https://github.com/lewis6991/gitsigns.nvim/issues/1372) ([83e29aa](https://github.com/lewis6991/gitsigns.nvim/commit/83e29aad7d9bc55fcc68ee6c74f8c92cae16869f))
* [#1384](https://github.com/lewis6991/gitsigns.nvim/issues/1384) ([cc2e664](https://github.com/lewis6991/gitsigns.nvim/commit/cc2e664c7e3cd8a31af34df040d16a75cfcadced))
* [#1388](https://github.com/lewis6991/gitsigns.nvim/issues/1388) ([c7d37ca](https://github.com/lewis6991/gitsigns.nvim/commit/c7d37ca22b461f64e26f8f6701b2586128ed0bef))
* add a 2s timeout to the git lock ([1bfeabd](https://github.com/lewis6991/gitsigns.nvim/commit/1bfeabdf1c21cb039cc2049d2519c3d1d48787c2))
* all toggle actions didn't refresh highlight in non-active buffers ([50a635b](https://github.com/lewis6991/gitsigns.nvim/commit/50a635b9bbd65a9b6d95e8ed7b7206348d11fde8))
* **async:** raise errors when they happen ([ee7e50d](https://github.com/lewis6991/gitsigns.nvim/commit/ee7e50dfbdf49e3acfa416fd3ad3abbdb658582c))
* attach through symlinks ([2ac55db](https://github.com/lewis6991/gitsigns.nvim/commit/2ac55dbde63eec1a41c65e6574a8ddef6d816262))
* **attach:** do not attach to files in resolved gitdir ([c80e0b4](https://github.com/lewis6991/gitsigns.nvim/commit/c80e0b4bfc411d5740a47adc8775fd1070f2028b)), closes [#1218](https://github.com/lewis6991/gitsigns.nvim/issues/1218)
* **attach:** don't skip all `.git*` files at the root of the repo ([362fe61](https://github.com/lewis6991/gitsigns.nvim/commit/362fe61f9f19e9bceff178792780df5cce118a7d))
* blame incompatible neovim function ([#1406](https://github.com/lewis6991/gitsigns.nvim/issues/1406)) ([400cfab](https://github.com/lewis6991/gitsigns.nvim/commit/400cfabf87fb3f7b48aa4eae1c11758e39a57071))
* blame_line{full=true} stop work ([27c3f37](https://github.com/lewis6991/gitsigns.nvim/commit/27c3f37a8ea6480ba336dab74f73a8032a0de63c))
* **blame:** always update current_line_blame on WinResized ([ea7c05f](https://github.com/lewis6991/gitsigns.nvim/commit/ea7c05f70214aed320ad6afa0718a9c15cf8cb12))
* **blame:** check valid buf ([58e3e52](https://github.com/lewis6991/gitsigns.nvim/commit/58e3e52e46c6abefd3dc8b6e246716e30ce771ef))
* **blame:** close blame window on bufhidden ([91f39eb](https://github.com/lewis6991/gitsigns.nvim/commit/91f39eb148fd984449203c29e169b614eea273b4))
* **blame:** do no expand hunk text ([425cb39](https://github.com/lewis6991/gitsigns.nvim/commit/425cb3942716554035ee56b0e36528355c238e3d))
* **blame:** do not show stale blames popup ([0c68263](https://github.com/lewis6991/gitsigns.nvim/commit/0c6826374f47fcbb2b53053986ccc59c115044ff))
* **blame:** do not unpack hunk linespec ([731b581](https://github.com/lewis6991/gitsigns.nvim/commit/731b581428ec6c1ccb451b95190ebbc6d7006db7))
* **blame:** get gh blame info asynchronously ([a434c8c](https://github.com/lewis6991/gitsigns.nvim/commit/a434c8cc97d8b96cb272e7a44112891d5a05bb06))
* **blame:** handle bad git-blame output ([07d4263](https://github.com/lewis6991/gitsigns.nvim/commit/07d426364c476e8a091ff7ee40b862f97e2cfb3c)), closes [#1332](https://github.com/lewis6991/gitsigns.nvim/issues/1332)
* **blame:** handle partial lines in blame output ([3d01bad](https://github.com/lewis6991/gitsigns.nvim/commit/3d01bad517a9cd8d6b1ac6871e16188375c2853b)), closes [#1236](https://github.com/lewis6991/gitsigns.nvim/issues/1236)
* **blame:** not stale if enter popup before result popup.update ([bf77caa](https://github.com/lewis6991/gitsigns.nvim/commit/bf77caa5da671f5bab16e4792711d5aa288e8db0))
* **blame:** remove link highlight on whitespace ([89f7507](https://github.com/lewis6991/gitsigns.nvim/commit/89f75073da1c8fab1d8b6285da72366ee54633ba))
* **blame:** set nolist in the blame window ([6067670](https://github.com/lewis6991/gitsigns.nvim/commit/60676707b6a5fa42369e8ff40a481ca45987e0d0))
* **cache:** correct condition for range blame ([3f5ffea](https://github.com/lewis6991/gitsigns.nvim/commit/3f5ffea8abbb3d58d536abfe65cb7e48caee38f5))
* calculate staged color dynamically adjust based on background ([d16d4ed](https://github.com/lewis6991/gitsigns.nvim/commit/d16d4ed864478c13d9bdd74230af0a4cc12e644b))
* check cwd before running rev-parse ([a3f64d4](https://github.com/lewis6991/gitsigns.nvim/commit/a3f64d4289f818bc5de66295a9696e2819bfb270)), closes [#1331](https://github.com/lewis6991/gitsigns.nvim/issues/1331)
* check preview popup before navigating ([e399f97](https://github.com/lewis6991/gitsigns.nvim/commit/e399f9748d7cfd8859747c8d6c4e9c8b4d50a1bd))
* Close blame buffer on closure of source buffer ([130beac](https://github.com/lewis6991/gitsigns.nvim/commit/130beacf8a51f00aede9c31064c749136679a321))
* correct hl group ([b79047e](https://github.com/lewis6991/gitsigns.nvim/commit/b79047e81f645875e500b4f433d8133bc421446c))
* do not attach if buffer is a directory ([392b9da](https://github.com/lewis6991/gitsigns.nvim/commit/392b9da4abebe9bee11b66dfdad82e0234bac4c2))
* do not attach to fugitive tree buffers ([472f752](https://github.com/lewis6991/gitsigns.nvim/commit/472f752943d44d732cece09d442d45681ce38f48))
* do not error if no gh remotes ([736f51d](https://github.com/lewis6991/gitsigns.nvim/commit/736f51d2bb684c06f39a2032f064d7244f549981))
* emmylua fixes ([7bbc674](https://github.com/lewis6991/gitsigns.nvim/commit/7bbc674278f22376850576dfdddf43bbc17e62b5))
* emmylua fixes ([c9165bb](https://github.com/lewis6991/gitsigns.nvim/commit/c9165bbc3266d14d557397baf42f4a2389acbe3d))
* error when `Gitsigns next_hunk target=all` ([4666d04](https://github.com/lewis6991/gitsigns.nvim/commit/4666d040b60d1dc0e474ccd9a3fd3c4d67b4767c))
* **error:** [#1277](https://github.com/lewis6991/gitsigns.nvim/issues/1277) ([9cd665f](https://github.com/lewis6991/gitsigns.nvim/commit/9cd665f46ab7af2e49d140d328b8e72ea1cf511b))
* errors nil ref ([43b0c85](https://github.com/lewis6991/gitsigns.nvim/commit/43b0c856ae5f32a195d83f4a27fe21d63e6c966c))
* force release lock if we waiting for more than 4 seconds ([24d4c92](https://github.com/lewis6991/gitsigns.nvim/commit/24d4c92dc635a445f309b7a5b99499d06714e2e8))
* handle files outside of repo ([1796c7c](https://github.com/lewis6991/gitsigns.nvim/commit/1796c7cedfe7e5dd20096c5d7b8b753d8f8d22eb)), closes [#1117](https://github.com/lewis6991/gitsigns.nvim/issues/1117) [#1296](https://github.com/lewis6991/gitsigns.nvim/issues/1296) [#1297](https://github.com/lewis6991/gitsigns.nvim/issues/1297)
* handle when files are removed from index ([fd50977](https://github.com/lewis6991/gitsigns.nvim/commit/fd50977fce4d5240b910d2b816e71fb726cbbaf7))
* **handle_blame_info:** do not consider `wrap/nowrap` for `right_align/eol` ([75879cd](https://github.com/lewis6991/gitsigns.nvim/commit/75879cd946b5d4aa922b9d96423bce092838be1a))
* make update lock disabled by default ([8270378](https://github.com/lewis6991/gitsigns.nvim/commit/8270378ab83540b03d09c0194ba3e208f9d0cb72))
* nvim&lt;0.11 has no `&winborder` ([2f0f65e](https://github.com/lewis6991/gitsigns.nvim/commit/2f0f65ed8002f2e3123035913c27b87c2d14e9d2))
* **popup:** don't move window when resizing ([20ad441](https://github.com/lewis6991/gitsigns.nvim/commit/20ad4419564d6e22b189f6738116b38871082332))
* prevent inline hunk preview from folding ([02eafb1](https://github.com/lewis6991/gitsigns.nvim/commit/02eafb1273afec94447f66d1a43fc5e477c2ab8a))
* preview_hunk format ([8bdaccd](https://github.com/lewis6991/gitsigns.nvim/commit/8bdaccdb897945a3c99c1ad8df94db0ddf5c8790))
* **preview:** set border to none for inline preview ([7cfd88d](https://github.com/lewis6991/gitsigns.nvim/commit/7cfd88d9c017283df14125640c9ce9c07f284519))
* react to config changes more robustly ([c4dbc36](https://github.com/lewis6991/gitsigns.nvim/commit/c4dbc3624999e9ddd9d1f5a6749f0a9346bfc2ed))
* remove border from docs ([be7640c](https://github.com/lewis6991/gitsigns.nvim/commit/be7640c55bf1306769f5cf3215d8cf52e80eba2c))
* remove clear_env=true for system calls ([03fb621](https://github.com/lewis6991/gitsigns.nvim/commit/03fb6212779fa62bde4176719383bcd658fd7963)), closes [#1350](https://github.com/lewis6991/gitsigns.nvim/issues/1350)
* remove duplicated phrase in comments of util.lua ([18ec9a8](https://github.com/lewis6991/gitsigns.nvim/commit/18ec9a862741453e0f47f28155728b11c992b5f4))
* repo memory leak ([1fcaddc](https://github.com/lewis6991/gitsigns.nvim/commit/1fcaddcc427ff5802b6602f46de37a5352d0f9e0))
* respect winborder when creating popups ([ce5e1b5](https://github.com/lewis6991/gitsigns.nvim/commit/ce5e1b5ae3455316364ac1c96c2787d7925a2914))
* **scm-rockspec:** add 'plugin' to copy_directories ([cdafc32](https://github.com/lewis6991/gitsigns.nvim/commit/cdafc320f03f2572c40ab93a4eecb733d4016d07))
* set more buf options in commit buffers ([c8ddbdb](https://github.com/lewis6991/gitsigns.nvim/commit/c8ddbdbce20d31561f6e19e7a3e9e8874714edfc))
* **show:** handle numeric branch name ([0b3ac7a](https://github.com/lewis6991/gitsigns.nvim/commit/0b3ac7a7cbb9999957bc5d8a1973214bfa37c3cf))
* tests for nightly ([00f1418](https://github.com/lewis6991/gitsigns.nvim/commit/00f14183abbcc38766d9d0b63f3f03174e3a3bd8))
* tracking multiple branch changes ([#1266](https://github.com/lewis6991/gitsigns.nvim/issues/1266)) ([2149fc2](https://github.com/lewis6991/gitsigns.nvim/commit/2149fc2009d1117d58e86e56836f70c969f60a82))
* type errors from emmylua ([5f1b1e2](https://github.com/lewis6991/gitsigns.nvim/commit/5f1b1e25373cd589ecf418ced8c2ece28229dd83))
* type errors from emmylua ([d1c3d5a](https://github.com/lewis6991/gitsigns.nvim/commit/d1c3d5af2cbe235def22006888df41fa22c1fd9c))
* type fixes ([24ecb13](https://github.com/lewis6991/gitsigns.nvim/commit/24ecb1375789bd3dec196f13d03163c0f0a68c47))
* **types:** add on_attach return type ([8b729e4](https://github.com/lewis6991/gitsigns.nvim/commit/8b729e489f1475615dc6c9737da917b3bc163605))
* vim.ui.select with Snacks ([f780609](https://github.com/lewis6991/gitsigns.nvim/commit/f780609807eca1f783a36a8a31c30a48fbe150c5))
* **watcher:** invalidate the cache earlier ([d600d39](https://github.com/lewis6991/gitsigns.nvim/commit/d600d3922c1d001422689319a8f915136bb64e1e))
* when diff dos format with unix format ([8820595](https://github.com/lewis6991/gitsigns.nvim/commit/88205953bd748322b49b26e1dfb0389932520dc9))
* **windows:** [#1250](https://github.com/lewis6991/gitsigns.nvim/issues/1250) ([140ac64](https://github.com/lewis6991/gitsigns.nvim/commit/140ac646db125904e456e42ab8b538d28f9607d7))
* **word_diff:** align inline preview highlights ([684270f](https://github.com/lewis6991/gitsigns.nvim/commit/684270f22364bd248fcedd51598b6433266fdc47))
* **word_diff:** no "No newline at end of file" shown in popup ([6bd2949](https://github.com/lewis6991/gitsigns.nvim/commit/6bd29494e3f79ff08be1d35bc1926ed23c22ed9a))


### Performance Improvements

* defer updates to hidden buffers ([3c69cac](https://github.com/lewis6991/gitsigns.nvim/commit/3c69cac2793cffa95cb62e8a457fe98f944133dc))
* ignore gitdir changes by watchmen ([e44821b](https://github.com/lewis6991/gitsigns.nvim/commit/e44821b9b50168a847b159f66c5c413ea2804f64))


### Continuous Integration

* target Nvim 0.11, drop testing for 0.9.5 ([3c76f7f](https://github.com/lewis6991/gitsigns.nvim/commit/3c76f7fabac723aa682365ef782f88a83ccdb4ac))

## [1.0.2](https://github.com/lewis6991/gitsigns.nvim/compare/v1.0.1...v1.0.2) (2025-03-16)


### Bug Fixes

* `stage_hunk` on staged hunk should behave like `undo_stage_hunk` ([5fefc7b](https://github.com/lewis6991/gitsigns.nvim/commit/5fefc7bf6966f9a1ca961ac2fca0f9d93118df18))
* change_base with empty base ([751bfae](https://github.com/lewis6991/gitsigns.nvim/commit/751bfae26a3561394afcafdf92b0dc52988ce436))

## [1.0.1](https://github.com/lewis6991/gitsigns.nvim/compare/v1.0.0...v1.0.1) (2025-02-15)


### Bug Fixes

* **blame:** fix popup menu shortcut mappings ([420b199](https://github.com/lewis6991/gitsigns.nvim/commit/420b19971c22ba7558dfd39ec1c1c2735c7db93f)), closes [#1215](https://github.com/lewis6991/gitsigns.nvim/issues/1215)
* **current_line_blame:** last line show not committed ([8b00147](https://github.com/lewis6991/gitsigns.nvim/commit/8b00147519d6f8353867d5d0b55f587306b0cfb6)), closes [#1213](https://github.com/lewis6991/gitsigns.nvim/issues/1213)
* stylua ([2bc3b47](https://github.com/lewis6991/gitsigns.nvim/commit/2bc3b472bbc2484214549af4d9f38c127b886a55))

## [1.0.0](https://github.com/lewis6991/gitsigns.nvim/compare/v0.9.0...v1.0.0) (2025-02-07)


### ⚠ BREAKING CHANGES

* deprecate some functions
* **blame:** replace dot with dash in blame file type name
* remove current_line_blame_formatter_opts
* remove support for yadm
* **config:** deprecate highlight groups in config.signs

### Features

* add highlights for the current line ([b29cb58](https://github.com/lewis6991/gitsigns.nvim/commit/b29cb58126663569f6f34401fab513c2375e95d3))
* add staging and update locks ([e6e3c3a](https://github.com/lewis6991/gitsigns.nvim/commit/e6e3c3a1394d9e0a1c75d8620f8631e4a6ecde0e))
* add submodule support for gitsigns urls ([f074844](https://github.com/lewis6991/gitsigns.nvim/commit/f074844b60f9e151970fbcdbeb8a2cd52b6ef25a)), closes [#1095](https://github.com/lewis6991/gitsigns.nvim/issues/1095)
* add type annotations for modules ([ac5aba6](https://github.com/lewis6991/gitsigns.nvim/commit/ac5aba6dce8c06ea22bea2c9016f51a2dbf90dc7))
* **async:** add async.pcall ([562dc47](https://github.com/lewis6991/gitsigns.nvim/commit/562dc47189ad3c8696dbf460d38603a74d544849))
* **blame_line:** add option to show when not focused ([2667904](https://github.com/lewis6991/gitsigns.nvim/commit/2667904fb0ee62832c55b56acb9ade3e02a0c202))
* **blame:** add `Gitsigns blame` ([25b6ee4](https://github.com/lewis6991/gitsigns.nvim/commit/25b6ee4be514b38d5bfe950d790a67042e05ef35))
* **blame:** add reblame at commit parent ([f4928ba](https://github.com/lewis6991/gitsigns.nvim/commit/f4928ba14eb6c667786ac7d69927f6aee6719f1e))
* **blame:** run formatter with pcall ([9ca00df](https://github.com/lewis6991/gitsigns.nvim/commit/9ca00df1c84fc0a1ed18c79156c06b081dc1da1f))
* **blame:** set filetype to gitsigns.blame ([0dc8866](https://github.com/lewis6991/gitsigns.nvim/commit/0dc886637f9686b7cfd245a4726f93abeab19d4a)), closes [#1049](https://github.com/lewis6991/gitsigns.nvim/issues/1049)
* **config:** deprecate highlight groups in config.signs ([3d7e49c](https://github.com/lewis6991/gitsigns.nvim/commit/3d7e49c201537ee0293a1a3abe67b67f8e7648a5))
* **config:** improve deprecation message ([fa42613](https://github.com/lewis6991/gitsigns.nvim/commit/fa42613096ebfa5fee1ea87d70f8625ab9685d01))
* deprecate some functions ([8b74e56](https://github.com/lewis6991/gitsigns.nvim/commit/8b74e560f7cba19b45b7d72a3cf8fb769316d259))
* detect repo errors ([899e993](https://github.com/lewis6991/gitsigns.nvim/commit/899e993850084ea33d001ec229d237bc020c19ae))
* **nav:** add target option ([9291836](https://github.com/lewis6991/gitsigns.nvim/commit/929183666540e164fa74028954ade62fa703fa1a))
* nicer errors for failed stages ([9521fe8](https://github.com/lewis6991/gitsigns.nvim/commit/9521fe8be39255b9abc6ec54e352bf04c410f5cf))
* remove current_line_blame_formatter_opts ([92a8fbb](https://github.com/lewis6991/gitsigns.nvim/commit/92a8fbb8453571978468e4ad2d4f8cd302d79eab))
* remove support for yadm ([61f5b64](https://github.com/lewis6991/gitsigns.nvim/commit/61f5b6407611a25e2d407ac0bc60e5c87c25ad72))
* set bufname for commit buffers ([e4efe9b](https://github.com/lewis6991/gitsigns.nvim/commit/e4efe9b99b7c473e9f917edf441cec48c05fd99e))
* share Repo objects across buffers ([2593efa](https://github.com/lewis6991/gitsigns.nvim/commit/2593efa3c53f41987d99bf8727f67154e88c0c91))
* **signs:** able staged signs by default ([b8cf5e8](https://github.com/lewis6991/gitsigns.nvim/commit/b8cf5e8efaa0036d493a2e2dfed768c3a03fac73))
* **signs:** improve sign generation from hunks ([2d2156a](https://github.com/lewis6991/gitsigns.nvim/commit/2d2156a2f8c6babbf5f10aea6df23993416f0f28))
* tweak how commit buffers are processed ([47c8e3e](https://github.com/lewis6991/gitsigns.nvim/commit/47c8e3e571376b24de62408fd0c9d12f0a9fc0a3))
* use luajit buffers to serialize thread data ([233bcbf](https://github.com/lewis6991/gitsigns.nvim/commit/233bcbfda3a04e19ae4fb365a8cbd32d9aa8c0d1))


### Bug Fixes

* [#1182](https://github.com/lewis6991/gitsigns.nvim/issues/1182) ([632fda7](https://github.com/lewis6991/gitsigns.nvim/commit/632fda72df903255dc1683cd739dceaa7338128a))
* [#1182](https://github.com/lewis6991/gitsigns.nvim/issues/1182) (take 2) ([3868c17](https://github.com/lewis6991/gitsigns.nvim/commit/3868c176d406b217ec8961e47ad033105ddc486c))
* [#1185](https://github.com/lewis6991/gitsigns.nvim/issues/1185) ([8fb9e75](https://github.com/lewis6991/gitsigns.nvim/commit/8fb9e7515d38c042f26bfa894a0b7cb36e27c895))
* [#1185](https://github.com/lewis6991/gitsigns.nvim/issues/1185) (take 2) ([fd7457f](https://github.com/lewis6991/gitsigns.nvim/commit/fd7457fa13b7b5c63b5dc164c6cbf9192fbe72d1))
* [#1185](https://github.com/lewis6991/gitsigns.nvim/issues/1185) (take 3) ([f301005](https://github.com/lewis6991/gitsigns.nvim/commit/f301005d8eaa15ef61ed6e7dbaa8c5193541ac37))
* [#1187](https://github.com/lewis6991/gitsigns.nvim/issues/1187) ([d8918f0](https://github.com/lewis6991/gitsigns.nvim/commit/d8918f06624dd53b9a82bd0e29c31bcfd541b40d))
* add cli binding for show ([d9f997d](https://github.com/lewis6991/gitsigns.nvim/commit/d9f997dba757be01434ed3538d202f88286df476))
* add nil check ([9d80331](https://github.com/lewis6991/gitsigns.nvim/commit/9d803313b7384bd52e0a9ad19307e9ae774fc926))
* add nil check ([7178d1a](https://github.com/lewis6991/gitsigns.nvim/commit/7178d1a430dcfff8a4c92d78b9e39e0297a779c0))
* **attach:** do not attach to fugitive directory buffers ([cf1ffe6](https://github.com/lewis6991/gitsigns.nvim/commit/cf1ffe682d3ac3a3cb89a7bdf50cc15ff1fadb8e)), closes [#1198](https://github.com/lewis6991/gitsigns.nvim/issues/1198)
* **attach:** resolve error viewing fugitive trees ([#1058](https://github.com/lewis6991/gitsigns.nvim/issues/1058)) ([89a4dce](https://github.com/lewis6991/gitsigns.nvim/commit/89a4dce7c94c40c89774d3cb3a7788a9ecf412c0))
* **blame:** ensure blame object is valid when all lines are requested ([817bd84](https://github.com/lewis6991/gitsigns.nvim/commit/817bd848fffe82e697b4da656e3f2834cd0665c5)), closes [#1156](https://github.com/lewis6991/gitsigns.nvim/issues/1156)
* **blame:** handle incremental output with a buffered reader ([e9c4187](https://github.com/lewis6991/gitsigns.nvim/commit/e9c4187c3774a46df2d086a66cf3a7e6bea4c432)), closes [#1084](https://github.com/lewis6991/gitsigns.nvim/issues/1084)
* **blame:** include error message in error ([d03a1c9](https://github.com/lewis6991/gitsigns.nvim/commit/d03a1c9a1045122823af97e351719227ed3718eb))
* **blame:** parse blame info correctly ([0595724](https://github.com/lewis6991/gitsigns.nvim/commit/0595724fa9516a35696ff6b1e3cb95b6462b38b1)), closes [#1065](https://github.com/lewis6991/gitsigns.nvim/issues/1065)
* **blame:** popupmenu error ([93c38d9](https://github.com/lewis6991/gitsigns.nvim/commit/93c38d97260330e8501ccda1e6000c858af0d603)), closes [#1061](https://github.com/lewis6991/gitsigns.nvim/issues/1061)
* **blame:** render blame end_col out of range ([aa12bb9](https://github.com/lewis6991/gitsigns.nvim/commit/aa12bb9cd22f1a612dd9cda6c6fc26475e94fc4f))
* **blame:** replace dot with dash in blame file type name ([0ed4669](https://github.com/lewis6991/gitsigns.nvim/commit/0ed466953fe5885166e0d60799172a8b1f752d16))
* **blame:** respect original blame winbar ([d0db8ef](https://github.com/lewis6991/gitsigns.nvim/commit/d0db8ef6a0489ed6af0baacb101a7b733c5d5de1))
* **blame:** restore original options when blame window is closed ([564849a](https://github.com/lewis6991/gitsigns.nvim/commit/564849a17bf5c5569e0bae98c8328de9c7a1ed29))
* **blame:** show current buffer line blame immediately ([6b1a14e](https://github.com/lewis6991/gitsigns.nvim/commit/6b1a14eabcebbcca1b9e9163a26b2f8371364cb7))
* **blame:** show same commit twice or more ([#1136](https://github.com/lewis6991/gitsigns.nvim/issues/1136)) ([ee7634a](https://github.com/lewis6991/gitsigns.nvim/commit/ee7634ab4f0a6606438fe13e16cbf2065589a5ed))
* **blame:** show the winbar if the main window has it enabled ([17e8fd6](https://github.com/lewis6991/gitsigns.nvim/commit/17e8fd66182c9ad79dc129451ad015af3d27529c))
* **blame:** track buffers changes correctly in the cache ([0349546](https://github.com/lewis6991/gitsigns.nvim/commit/0349546134d8a3a3c3a33e2e781b8d7bd07ea156))
* **blame:** update current_line_blame when attaching ([8df63f2](https://github.com/lewis6991/gitsigns.nvim/commit/8df63f2ddc615feb71fd4aee45a4cee022876df1))
* change assert to eprint ([7c27a30](https://github.com/lewis6991/gitsigns.nvim/commit/7c27a30450130cd59c4994a6755e3c5d74d83e76))
* derive Staged*Cul highlight correctly ([1d2cb56](https://github.com/lewis6991/gitsigns.nvim/commit/1d2cb568a7105a860941ef45a01b13709d7aa9d2))
* diffthis vertical option ([dcdcfcb](https://github.com/lewis6991/gitsigns.nvim/commit/dcdcfcb15eb7c6fc6023dbf03e9644e9d5b2f484))
* do not mix staged signs with normal signs ([9541f5e](https://github.com/lewis6991/gitsigns.nvim/commit/9541f5e8e24571723cb02a5c2bf078aeacc5a711)), closes [#1152](https://github.com/lewis6991/gitsigns.nvim/issues/1152)
* do not show staged signs for different bases ([0edca9d](https://github.com/lewis6991/gitsigns.nvim/commit/0edca9d1a06db1ae95d79c210825711172fb2802)), closes [#1118](https://github.com/lewis6991/gitsigns.nvim/issues/1118)
* **docs:** Add signs_staged to default config in README ([d44a794](https://github.com/lewis6991/gitsigns.nvim/commit/d44a7948ffc717af578c424add818b7684c7ed68))
* fileformat autocmd bug ([f41b934](https://github.com/lewis6991/gitsigns.nvim/commit/f41b934e70e2ae9b0a7a3cb1a5a7d172a4d8f1fd)), closes [#1123](https://github.com/lewis6991/gitsigns.nvim/issues/1123)
* get the repo version of the username ([2e5719c](https://github.com/lewis6991/gitsigns.nvim/commit/2e5719c79aead05c4269d6bd250acbc9c4d26d37))
* GitSignsChanged autocmd for staged hunks ([ac38d78](https://github.com/lewis6991/gitsigns.nvim/commit/ac38d7860b258ec07085d8d1931e1a487bcee21d)), closes [#1168](https://github.com/lewis6991/gitsigns.nvim/issues/1168)
* handle repos with no commits ([0cd4f0a](https://github.com/lewis6991/gitsigns.nvim/commit/0cd4f0aa1067b7261f0649b3124e1159dac3df8b))
* handle terminal-only highlights ([356df59](https://github.com/lewis6991/gitsigns.nvim/commit/356df59308d8b87486644d2324d7558ac0f3db36))
* help triggering text autocmds ([2a7b39f](https://github.com/lewis6991/gitsigns.nvim/commit/2a7b39f4d282935f8b44cbe82879af69c7472f5c))
* improve support for worktrees in bare repos ([6811483](https://github.com/lewis6991/gitsigns.nvim/commit/68114837e81ca16d06514c3a997c9102d1b25c15)), closes [#1160](https://github.com/lewis6991/gitsigns.nvim/issues/1160)
* lint ([39b5b6f](https://github.com/lewis6991/gitsigns.nvim/commit/39b5b6f48bde0595ce68007ffce408c5d7ac1f79))
* more EOL fixes ([f10fdda](https://github.com/lewis6991/gitsigns.nvim/commit/f10fddafe06f7ab7931031b394a26b2f3f434f3e)), closes [#1145](https://github.com/lewis6991/gitsigns.nvim/issues/1145)
* **nav:** misc bugs ([7516bac](https://github.com/lewis6991/gitsigns.nvim/commit/7516bac5639a9ce8e7b199066199a02cb3057230))
* nil check for repo cache ([375c44b](https://github.com/lewis6991/gitsigns.nvim/commit/375c44bdfdde25585466a966f00c2e291db74f2d))
* nil check for repo info ([e784e5a](https://github.com/lewis6991/gitsigns.nvim/commit/e784e5a078f993f7218b8a857cb581d5b9ca42dc))
* partial staging of staged signs ([31d2dcd](https://github.com/lewis6991/gitsigns.nvim/commit/31d2dcd144c7404dacbd2ca36b5abd37cc9fa506))
* random errors from blame autocommands ([#1139](https://github.com/lewis6991/gitsigns.nvim/issues/1139)) ([2d725fd](https://github.com/lewis6991/gitsigns.nvim/commit/2d725fdd7fe4a612fa3171ca0a965f455d8dc325))
* **repo:** make sure --git-dir is always provided --work-tree ([310018d](https://github.com/lewis6991/gitsigns.nvim/commit/310018d54357b8a3cbbcd2b7f589d12e61d2db35))
* reset diff when quiting diff buffer ([b544bd6](https://github.com/lewis6991/gitsigns.nvim/commit/b544bd62623ca1b483d8b9bfb6d65805f112a320)), closes [#1155](https://github.com/lewis6991/gitsigns.nvim/issues/1155)
* revision buffer name parsing for index buffers ([76d88f3](https://github.com/lewis6991/gitsigns.nvim/commit/76d88f3b584e1f83b2aa51663a32cc6ee8d97eff))
* select hunk gets all adjacent linematch hunks ([abc6dec](https://github.com/lewis6991/gitsigns.nvim/commit/abc6dec92232944108250e321858014bf79de245)), closes [#1133](https://github.com/lewis6991/gitsigns.nvim/issues/1133)
* **select_hunk:** compatible with &lt;cmd&gt; mapping ([8974fd3](https://github.com/lewis6991/gitsigns.nvim/commit/8974fd397e854bfa13a5130dc32ee357dbade276))
* setqflist("all") should respect change_base ([58bd9e9](https://github.com/lewis6991/gitsigns.nvim/commit/58bd9e98d8e3c5a1c98af312e85247ee1afd3ed2))
* **signs:** avoid placing signs on lnum 0 ([2f9f20e](https://github.com/lewis6991/gitsigns.nvim/commit/2f9f20ea3baacc077e940b7878a46a8295129418))
* sort get_nav_hunks to handle mixed hunk states ([80214a8](https://github.com/lewis6991/gitsigns.nvim/commit/80214a857ce512cc64964abddc1d8eb5a3e28396))
* string.buffer not found ([8639036](https://github.com/lewis6991/gitsigns.nvim/commit/863903631e676b33e8be2acb17512fdc1b80b4fb)), closes [#1126](https://github.com/lewis6991/gitsigns.nvim/issues/1126)
* support blame for git &lt; 2.41 ([a5b801e](https://github.com/lewis6991/gitsigns.nvim/commit/a5b801e7b16220e75d459919edcb5eb37b1de9cb)), closes [#1093](https://github.com/lewis6991/gitsigns.nvim/issues/1093)
* toggle_current_line_blame ([0e39e9a](https://github.com/lewis6991/gitsigns.nvim/commit/0e39e9afcfc180d55ac8f0691a230703683ddb0f)), closes [#1072](https://github.com/lewis6991/gitsigns.nvim/issues/1072)
* typo on dprint ([6f8dbdb](https://github.com/lewis6991/gitsigns.nvim/commit/6f8dbdbd41725fa11178e78d6e4c987038a8ece9))
* upstream fixes for system() ([c2a2739](https://github.com/lewis6991/gitsigns.nvim/commit/c2a273980eb2cbcabcd54690f06f041ea0c225c6))
* use non-deprecated versions of vim.validate ([0883d0f](https://github.com/lewis6991/gitsigns.nvim/commit/0883d0f67c1b728713deeddfcec4aabf71410801))
* use norm! to prevent user remapping ([4daf702](https://github.com/lewis6991/gitsigns.nvim/commit/4daf7022f1481edf1e8fb9947df13bb07c18e89a))
* **util:** ignore endofline when running blame ([def49e4](https://github.com/lewis6991/gitsigns.nvim/commit/def49e48c6329527e344d0c99a0d2cd9fdf6bb84))
* wait for buffer to attach in M.show ([1c128d4](https://github.com/lewis6991/gitsigns.nvim/commit/1c128d4585d89f39ddea9ef9f5f6b84edd3b66b9)), closes [#1091](https://github.com/lewis6991/gitsigns.nvim/issues/1091)
* **watcher:** do not ignore any updates ([5840f89](https://github.com/lewis6991/gitsigns.nvim/commit/5840f89c50b7af6b2f9c30e7fe37b797aef60ba9))
* **watcher:** fix debounce ([f846c50](https://github.com/lewis6991/gitsigns.nvim/commit/f846c507242a74d9a458bff2d029bd2eae8c0ca1)), closes [#1046](https://github.com/lewis6991/gitsigns.nvim/issues/1046)
* wipeout buf after closing the blame_line/preview_hunk window ([abcd00a](https://github.com/lewis6991/gitsigns.nvim/commit/abcd00a7d5bc1a9470cb21b023c575acade3e4db))


### Performance Improvements

* **blame:** some improvements ([9cdfcb5](https://github.com/lewis6991/gitsigns.nvim/commit/9cdfcb5f038586c36ad8b010f7e479f6a6f95a63))

## [0.9.0](https://github.com/lewis6991/gitsigns.nvim/compare/v0.8.1...v0.9.0) (2024-06-12)


### ⚠ BREAKING CHANGES

* **setup:** make setup() synchronous
* drop support for nvim v0.8

### Features

* drop support for nvim v0.8 ([d9d94e0](https://github.com/lewis6991/gitsigns.nvim/commit/d9d94e055a19415767bb073e8dd86028105c4319))
* **setup:** make setup() synchronous ([720061a](https://github.com/lewis6991/gitsigns.nvim/commit/720061aa152faedfe4099dfb92d2b3fcb0e55edc))


### Bug Fixes

* add workaround for Lazy issue ([e31d214](https://github.com/lewis6991/gitsigns.nvim/commit/e31d2149d9f3fb056bfd5b3416b2e818be10aabe))
* **attach:** allow attaching inside .git/ ([9cafac3](https://github.com/lewis6991/gitsigns.nvim/commit/9cafac31a091267838e1e90fd6e083d37611f516)), closes [#923](https://github.com/lewis6991/gitsigns.nvim/issues/923)
* **attach:** detach on when the buffer name changes ([75dc649](https://github.com/lewis6991/gitsigns.nvim/commit/75dc649106827183547d3bedd4602442340d2f7f)), closes [#1021](https://github.com/lewis6991/gitsigns.nvim/issues/1021)
* **attach:** fix worktree attaching ([54b9df4](https://github.com/lewis6991/gitsigns.nvim/commit/54b9df401b8f21f4e6ca537ec47a109394aaccd7)), closes [#1020](https://github.com/lewis6991/gitsigns.nvim/issues/1020)
* **blame:** avoid right-aligned blame overlapping buftext ([20f305d](https://github.com/lewis6991/gitsigns.nvim/commit/20f305d63bc86852821ac47d9967e73931f7130b))
* handle untracked files for custom bases ([af3fdad](https://github.com/lewis6991/gitsigns.nvim/commit/af3fdad8ddcadbdad835975204f6503310526fd9)), closes [#1022](https://github.com/lewis6991/gitsigns.nvim/issues/1022)
* scheduling in cwd watching ([c96e3cf](https://github.com/lewis6991/gitsigns.nvim/commit/c96e3cf4767ee98030bff855e7a6f07cfc6d427f))
* **update:** always get object contents from object names ([a28bb1d](https://github.com/lewis6991/gitsigns.nvim/commit/a28bb1db506df663b063cc63f44fbbda178255a7)), closes [#847](https://github.com/lewis6991/gitsigns.nvim/issues/847)
* use latest api in 0.10 ([bc933d2](https://github.com/lewis6991/gitsigns.nvim/commit/bc933d24a669608968ff4791b14d2d9554813a65))
* **util:** close file after reading ([f65d1d8](https://github.com/lewis6991/gitsigns.nvim/commit/f65d1d82013e032ca6c199b62f08089b420b068c))
* **watcher:** throttle watcher handler ([de18f6b](https://github.com/lewis6991/gitsigns.nvim/commit/de18f6b749f6129eb9042a2038590872df4c94a9))
* **watcher:** workaround weird annoying libuv bug ([4b53134](https://github.com/lewis6991/gitsigns.nvim/commit/4b53134ce5fdd58e6c52c49fb906b6e7a347d137)), closes [#1027](https://github.com/lewis6991/gitsigns.nvim/issues/1027)
* wrong api name in stable ([805610a](https://github.com/lewis6991/gitsigns.nvim/commit/805610a9393fa231f2c2b49cb521bfa413fadb3d))

## [0.8.1](https://github.com/lewis6991/gitsigns.nvim/compare/v0.8.0...v0.8.1) (2024-04-30)


### Bug Fixes

* **blame:** check win is valid after running blame ([7e38f07](https://github.com/lewis6991/gitsigns.nvim/commit/7e38f07cab0e5387f9f41e92474db174a63a4725))
* **reset:** handle 'endofline' when resetting hunks ([7aa9a56](https://github.com/lewis6991/gitsigns.nvim/commit/7aa9a567127d679c6ca639e9e88c546d72924296))
* **yadm:** correct ls-files check ([035da03](https://github.com/lewis6991/gitsigns.nvim/commit/035da036e68e509ed158414416c827d022d914bd))

## [0.8.0](https://github.com/lewis6991/gitsigns.nvim/compare/v0.7.0...v0.8.0) (2024-04-17)


### ⚠ BREAKING CHANGES

* **docs:** Use the new attached_to_untracked setting
* change default of attached_to_untracked to false

### Features

* **actions:** add callback to async actions ([4e90cf9](https://github.com/lewis6991/gitsigns.nvim/commit/4e90cf984ced787b7439c42678ec957da3583049))
* **blame:** add rev option to blame_line() ([0994d89](https://github.com/lewis6991/gitsigns.nvim/commit/0994d89323c2ebb4abb38cab15aad00913588b0f)), closes [#952](https://github.com/lewis6991/gitsigns.nvim/issues/952)
* **blame:** support extra options ([3358280](https://github.com/lewis6991/gitsigns.nvim/commit/3358280054808b45f711191df481fcffc12ca761)), closes [#953](https://github.com/lewis6991/gitsigns.nvim/issues/953) [#959](https://github.com/lewis6991/gitsigns.nvim/issues/959)
* change default of attached_to_untracked to false ([590d077](https://github.com/lewis6991/gitsigns.nvim/commit/590d077c551c0bd2fc8b9f658e4704ccd0423a2e))
* configurable auto attach ([#918](https://github.com/lewis6991/gitsigns.nvim/issues/918)) ([3e6e91b](https://github.com/lewis6991/gitsigns.nvim/commit/3e6e91b09f0468c32d3b96dcacf4b947f037ce25))
* enable the new version of inline_preview ([d195f0c](https://github.com/lewis6991/gitsigns.nvim/commit/d195f0c35ced5174d3ecce1c4c8ebb3b5bc23fa9))
* **nav:** add nav_hunk() ([59bdc18](https://github.com/lewis6991/gitsigns.nvim/commit/59bdc1851c7aba8a86ded87fe075ef6de499045c))
* **popup:** add `q` keymap to quit ([b45ff86](https://github.com/lewis6991/gitsigns.nvim/commit/b45ff86f5618d1421a88c12d4feb286b80a1e2d3))
* publish releases to luarocks ([070875f](https://github.com/lewis6991/gitsigns.nvim/commit/070875f9e4eb81eb20cb60996cd1d9086d94b05e))
* update issue templates ([e93a158](https://github.com/lewis6991/gitsigns.nvim/commit/e93a158b8773946dc9940a4321d35c1b52c8e293))
* **yadm:** deprecate ([1bb277b](https://github.com/lewis6991/gitsigns.nvim/commit/1bb277b41d65f68b091e4ab093f59e68a0def2a6))


### Bug Fixes

* [#986](https://github.com/lewis6991/gitsigns.nvim/issues/986) ([05226b4](https://github.com/lewis6991/gitsigns.nvim/commit/05226b4d41226af8045841b3e56b6cc12d7a1cd0))
* [#989](https://github.com/lewis6991/gitsigns.nvim/issues/989) ([36d961d](https://github.com/lewis6991/gitsigns.nvim/commit/36d961d3d11b72229aaa576dfc8e7f5e05510af8))
* **actions:** prev_hunk works with wrap on line 1 ([2b96835](https://github.com/lewis6991/gitsigns.nvim/commit/2b96835a2b700f31303ebad0696f0abdbe8477ed)), closes [#806](https://github.com/lewis6991/gitsigns.nvim/issues/806)
* attach to fugitive and gitsigns buffers ([81369ed](https://github.com/lewis6991/gitsigns.nvim/commit/81369ed5405ec0c5d55a9608b495dbf827415116)), closes [#593](https://github.com/lewis6991/gitsigns.nvim/issues/593)
* bad deprecation message ([a4db718](https://github.com/lewis6991/gitsigns.nvim/commit/a4db718c78bff65198e3b63f1043f1e7bb5e05c8)), closes [#965](https://github.com/lewis6991/gitsigns.nvim/issues/965)
* **blame:** check buffer still exists after loading ([70584ff](https://github.com/lewis6991/gitsigns.nvim/commit/70584ff9aae8078b64430c574079d79620b8f06d)), closes [#946](https://github.com/lewis6991/gitsigns.nvim/issues/946)
* **blame:** put ignore-revs-file in correct position ([5f267aa](https://github.com/lewis6991/gitsigns.nvim/commit/5f267aa2fec145eb9fa11be8ae7b3d8b1939fe00)), closes [#975](https://github.com/lewis6991/gitsigns.nvim/issues/975)
* changedelete symbol with linematch enabled ([41dc075](https://github.com/lewis6991/gitsigns.nvim/commit/41dc075ef67b556b0752ad3967649371bd95cb95))
* check bcache in get_hunks ([1a50b94](https://github.com/lewis6991/gitsigns.nvim/commit/1a50b94066def8591d5f65bd60a4233902e9def4)), closes [#979](https://github.com/lewis6991/gitsigns.nvim/issues/979) [#981](https://github.com/lewis6991/gitsigns.nvim/issues/981)
* check for WinResized ([c093623](https://github.com/lewis6991/gitsigns.nvim/commit/c0936237f24d01eb4974dd3de38df7888414be3e))
* **cli:** do not print result ([7e31d81](https://github.com/lewis6991/gitsigns.nvim/commit/7e31d8123f14d55f4a3f982d05ddae4f3bf9276a))
* **current_line_blame:** update on WinResized ([f0733b7](https://github.com/lewis6991/gitsigns.nvim/commit/f0733b793a5e2663fd6d101de5beda68eec33967)), closes [#966](https://github.com/lewis6991/gitsigns.nvim/issues/966)
* **diffthis:** populate b:gitsigns_head ([50577f0](https://github.com/lewis6991/gitsigns.nvim/commit/50577f0186686b404d12157d463fb6bc4abba726)), closes [#949](https://github.com/lewis6991/gitsigns.nvim/issues/949)
* do not error when cwd does not exist ([826ad69](https://github.com/lewis6991/gitsigns.nvim/commit/826ad6942907ff08b02b8310b783e7275fdfb761))
* **docs:** Use the new attached_to_untracked setting ([2c2463d](https://github.com/lewis6991/gitsigns.nvim/commit/2c2463dbd82eddd7dbab881c3a62cfbfbe3c67ae))
* **dos:** correct check for dos files ([aeab36f](https://github.com/lewis6991/gitsigns.nvim/commit/aeab36f4b5524a765381ef84a2c57b2e799c934d))
* followup ([690f298](https://github.com/lewis6991/gitsigns.nvim/commit/690f298c4cac9190ddb7eedeeee2a3cc446622f7))
* **git:** support older versions of git ([4e34864](https://github.com/lewis6991/gitsigns.nvim/commit/4e348641b8206c3b8d23080999e3ddbe4ca90efc))
* **hl:** highlights for Nvim v0.9 ([fb9fd53](https://github.com/lewis6991/gitsigns.nvim/commit/fb9fd5312476b51a42a98122616e1c448d823d5c)), closes [#939](https://github.com/lewis6991/gitsigns.nvim/issues/939)
* **manager:** manager.update() never resolve when buf_check() fails ([6e05045](https://github.com/lewis6991/gitsigns.nvim/commit/6e05045fb1a4845fe44f5c54aafe024444c422ba))
* **nav:** followup for [#976](https://github.com/lewis6991/gitsigns.nvim/issues/976) ([ee5b6ba](https://github.com/lewis6991/gitsigns.nvim/commit/ee5b6ba0b55707628704bcd8d3554d1a05207b99))
* release-please branch ([031abb0](https://github.com/lewis6991/gitsigns.nvim/commit/031abb065452248c30ce8d8fb4d4eb9eeb69d1f0))
* **setqflist:** CLI ([e20c96e](https://github.com/lewis6991/gitsigns.nvim/commit/e20c96e9c3b9b2241939ce437d03926ba7315eaa)), closes [#907](https://github.com/lewis6991/gitsigns.nvim/issues/907)
* **stage:** staging of files with no nl at eof ([c097cb2](https://github.com/lewis6991/gitsigns.nvim/commit/c097cb255096f333e14d341082a84f572b394fa2))
* trigger GitSignsUpdate autocmd more often ([1389134](https://github.com/lewis6991/gitsigns.nvim/commit/1389134ba94643dd3b8ce2e1bf142d1c0432a4f2))
* typo in README ([4aaacbf](https://github.com/lewis6991/gitsigns.nvim/commit/4aaacbf5e5e2218fd05eb75703fe9e0f85335803))
* update lua-guide link in README ([c5ff762](https://github.com/lewis6991/gitsigns.nvim/commit/c5ff7628e19a47ec14d3657294cc074ecae27b99))
* use documented highlight groups as fallback ([300a306](https://github.com/lewis6991/gitsigns.nvim/commit/300a306da9973e81c2c06460f71fd7a079df1f36))
* **version:** handle version checks more gracefully ([3cb0f84](https://github.com/lewis6991/gitsigns.nvim/commit/3cb0f8431f56996a4af2924d78a98a09b6add095)), closes [#948](https://github.com/lewis6991/gitsigns.nvim/issues/948) [#960](https://github.com/lewis6991/gitsigns.nvim/issues/960)
* **watcher:** improve buffer check in handler ([078041e](https://github.com/lewis6991/gitsigns.nvim/commit/078041e9d060a386b0c9d3a8c7a7b019a35d3fb0))
