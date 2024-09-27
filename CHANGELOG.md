# Changelog

## [1.0.0](https://github.com/lewis6991/gitsigns.nvim/compare/v0.9.0...v1.0.0) (2024-09-27)


### ⚠ BREAKING CHANGES

* **blame:** replace dot with dash in blame file type name
* remove current_line_blame_formatter_opts
* remove support for yadm
* **config:** deprecate highlight groups in config.signs

### Features

* add highlights for the current line ([b29cb58](https://github.com/lewis6991/gitsigns.nvim/commit/b29cb58126663569f6f34401fab513c2375e95d3))
* add staging and update locks ([e6e3c3a](https://github.com/lewis6991/gitsigns.nvim/commit/e6e3c3a1394d9e0a1c75d8620f8631e4a6ecde0e))
* add submodule support for gitsigns urls ([f074844](https://github.com/lewis6991/gitsigns.nvim/commit/f074844b60f9e151970fbcdbeb8a2cd52b6ef25a)), closes [#1095](https://github.com/lewis6991/gitsigns.nvim/issues/1095)
* **async:** add async.pcall ([562dc47](https://github.com/lewis6991/gitsigns.nvim/commit/562dc47189ad3c8696dbf460d38603a74d544849))
* **blame_line:** add option to show when not focused ([2667904](https://github.com/lewis6991/gitsigns.nvim/commit/2667904fb0ee62832c55b56acb9ade3e02a0c202))
* **blame:** add `Gitsigns blame` ([25b6ee4](https://github.com/lewis6991/gitsigns.nvim/commit/25b6ee4be514b38d5bfe950d790a67042e05ef35))
* **blame:** add reblame at commit parent ([f4928ba](https://github.com/lewis6991/gitsigns.nvim/commit/f4928ba14eb6c667786ac7d69927f6aee6719f1e))
* **blame:** run formatter with pcall ([9ca00df](https://github.com/lewis6991/gitsigns.nvim/commit/9ca00df1c84fc0a1ed18c79156c06b081dc1da1f))
* **blame:** set filetype to gitsigns.blame ([0dc8866](https://github.com/lewis6991/gitsigns.nvim/commit/0dc886637f9686b7cfd245a4726f93abeab19d4a)), closes [#1049](https://github.com/lewis6991/gitsigns.nvim/issues/1049)
* **config:** deprecate highlight groups in config.signs ([3d7e49c](https://github.com/lewis6991/gitsigns.nvim/commit/3d7e49c201537ee0293a1a3abe67b67f8e7648a5))
* **config:** improve deprecation message ([fa42613](https://github.com/lewis6991/gitsigns.nvim/commit/fa42613096ebfa5fee1ea87d70f8625ab9685d01))
* detect repo errors ([899e993](https://github.com/lewis6991/gitsigns.nvim/commit/899e993850084ea33d001ec229d237bc020c19ae))
* **nav:** add target option ([9291836](https://github.com/lewis6991/gitsigns.nvim/commit/929183666540e164fa74028954ade62fa703fa1a))
* remove current_line_blame_formatter_opts ([92a8fbb](https://github.com/lewis6991/gitsigns.nvim/commit/92a8fbb8453571978468e4ad2d4f8cd302d79eab))
* remove support for yadm ([61f5b64](https://github.com/lewis6991/gitsigns.nvim/commit/61f5b6407611a25e2d407ac0bc60e5c87c25ad72))
* set bufname for commit buffers ([e4efe9b](https://github.com/lewis6991/gitsigns.nvim/commit/e4efe9b99b7c473e9f917edf441cec48c05fd99e))
* share Repo objects across buffers ([2593efa](https://github.com/lewis6991/gitsigns.nvim/commit/2593efa3c53f41987d99bf8727f67154e88c0c91))
* **signs:** able staged signs by default ([b8cf5e8](https://github.com/lewis6991/gitsigns.nvim/commit/b8cf5e8efaa0036d493a2e2dfed768c3a03fac73))
* tweak how commit buffers are processed ([47c8e3e](https://github.com/lewis6991/gitsigns.nvim/commit/47c8e3e571376b24de62408fd0c9d12f0a9fc0a3))
* use luajit buffers to serialize thread data ([233bcbf](https://github.com/lewis6991/gitsigns.nvim/commit/233bcbfda3a04e19ae4fb365a8cbd32d9aa8c0d1))


### Bug Fixes

* add cli binding for show ([d9f997d](https://github.com/lewis6991/gitsigns.nvim/commit/d9f997dba757be01434ed3538d202f88286df476))
* add nil check ([7178d1a](https://github.com/lewis6991/gitsigns.nvim/commit/7178d1a430dcfff8a4c92d78b9e39e0297a779c0))
* **attach:** resolve error viewing fugitive trees ([#1058](https://github.com/lewis6991/gitsigns.nvim/issues/1058)) ([89a4dce](https://github.com/lewis6991/gitsigns.nvim/commit/89a4dce7c94c40c89774d3cb3a7788a9ecf412c0))
* **blame:** handle incremental output with a buffered reader ([e9c4187](https://github.com/lewis6991/gitsigns.nvim/commit/e9c4187c3774a46df2d086a66cf3a7e6bea4c432)), closes [#1084](https://github.com/lewis6991/gitsigns.nvim/issues/1084)
* **blame:** include error message in error ([d03a1c9](https://github.com/lewis6991/gitsigns.nvim/commit/d03a1c9a1045122823af97e351719227ed3718eb))
* **blame:** parse blame info correctly ([0595724](https://github.com/lewis6991/gitsigns.nvim/commit/0595724fa9516a35696ff6b1e3cb95b6462b38b1)), closes [#1065](https://github.com/lewis6991/gitsigns.nvim/issues/1065)
* **blame:** popupmenu error ([93c38d9](https://github.com/lewis6991/gitsigns.nvim/commit/93c38d97260330e8501ccda1e6000c858af0d603)), closes [#1061](https://github.com/lewis6991/gitsigns.nvim/issues/1061)
* **blame:** render blame end_col out of range ([aa12bb9](https://github.com/lewis6991/gitsigns.nvim/commit/aa12bb9cd22f1a612dd9cda6c6fc26475e94fc4f))
* **blame:** replace dot with dash in blame file type name ([0ed4669](https://github.com/lewis6991/gitsigns.nvim/commit/0ed466953fe5885166e0d60799172a8b1f752d16))
* **blame:** respect original blame winbar ([d0db8ef](https://github.com/lewis6991/gitsigns.nvim/commit/d0db8ef6a0489ed6af0baacb101a7b733c5d5de1))
* **blame:** restore original options when blame window is closed ([564849a](https://github.com/lewis6991/gitsigns.nvim/commit/564849a17bf5c5569e0bae98c8328de9c7a1ed29))
* **blame:** show current buffer line blame immediately ([6b1a14e](https://github.com/lewis6991/gitsigns.nvim/commit/6b1a14eabcebbcca1b9e9163a26b2f8371364cb7))
* **blame:** show the winbar if the main window has it enabled ([17e8fd6](https://github.com/lewis6991/gitsigns.nvim/commit/17e8fd66182c9ad79dc129451ad015af3d27529c))
* **blame:** track buffers changes correctly in the cache ([0349546](https://github.com/lewis6991/gitsigns.nvim/commit/0349546134d8a3a3c3a33e2e781b8d7bd07ea156))
* **blame:** update current_line_blame when attaching ([8df63f2](https://github.com/lewis6991/gitsigns.nvim/commit/8df63f2ddc615feb71fd4aee45a4cee022876df1))
* derive Staged*Cul highlight correctly ([1d2cb56](https://github.com/lewis6991/gitsigns.nvim/commit/1d2cb568a7105a860941ef45a01b13709d7aa9d2))
* diffthis vertical option ([dcdcfcb](https://github.com/lewis6991/gitsigns.nvim/commit/dcdcfcb15eb7c6fc6023dbf03e9644e9d5b2f484))
* **docs:** Add signs_staged to default config in README ([d44a794](https://github.com/lewis6991/gitsigns.nvim/commit/d44a7948ffc717af578c424add818b7684c7ed68))
* get the repo version of the username ([2e5719c](https://github.com/lewis6991/gitsigns.nvim/commit/2e5719c79aead05c4269d6bd250acbc9c4d26d37))
* handle repos with no commits ([0cd4f0a](https://github.com/lewis6991/gitsigns.nvim/commit/0cd4f0aa1067b7261f0649b3124e1159dac3df8b))
* handle terminal-only highlights ([356df59](https://github.com/lewis6991/gitsigns.nvim/commit/356df59308d8b87486644d2324d7558ac0f3db36))
* help triggering text autocmds ([2a7b39f](https://github.com/lewis6991/gitsigns.nvim/commit/2a7b39f4d282935f8b44cbe82879af69c7472f5c))
* lint ([39b5b6f](https://github.com/lewis6991/gitsigns.nvim/commit/39b5b6f48bde0595ce68007ffce408c5d7ac1f79))
* **nav:** misc bugs ([7516bac](https://github.com/lewis6991/gitsigns.nvim/commit/7516bac5639a9ce8e7b199066199a02cb3057230))
* nil check for repo cache ([375c44b](https://github.com/lewis6991/gitsigns.nvim/commit/375c44bdfdde25585466a966f00c2e291db74f2d))
* nil check for repo info ([e784e5a](https://github.com/lewis6991/gitsigns.nvim/commit/e784e5a078f993f7218b8a857cb581d5b9ca42dc))
* setqflist("all") should respect change_base ([58bd9e9](https://github.com/lewis6991/gitsigns.nvim/commit/58bd9e98d8e3c5a1c98af312e85247ee1afd3ed2))
* sort get_nav_hunks to handle mixed hunk states ([80214a8](https://github.com/lewis6991/gitsigns.nvim/commit/80214a857ce512cc64964abddc1d8eb5a3e28396))
* string.buffer not found ([8639036](https://github.com/lewis6991/gitsigns.nvim/commit/863903631e676b33e8be2acb17512fdc1b80b4fb)), closes [#1126](https://github.com/lewis6991/gitsigns.nvim/issues/1126)
* toggle_current_line_blame ([0e39e9a](https://github.com/lewis6991/gitsigns.nvim/commit/0e39e9afcfc180d55ac8f0691a230703683ddb0f)), closes [#1072](https://github.com/lewis6991/gitsigns.nvim/issues/1072)
* typo on dprint ([6f8dbdb](https://github.com/lewis6991/gitsigns.nvim/commit/6f8dbdbd41725fa11178e78d6e4c987038a8ece9))
* **util:** ignore endofline when running blame ([def49e4](https://github.com/lewis6991/gitsigns.nvim/commit/def49e48c6329527e344d0c99a0d2cd9fdf6bb84))
* wait for buffer to attach in M.show ([1c128d4](https://github.com/lewis6991/gitsigns.nvim/commit/1c128d4585d89f39ddea9ef9f5f6b84edd3b66b9)), closes [#1091](https://github.com/lewis6991/gitsigns.nvim/issues/1091)
* **watcher:** do not ignore any updates ([5840f89](https://github.com/lewis6991/gitsigns.nvim/commit/5840f89c50b7af6b2f9c30e7fe37b797aef60ba9))
* **watcher:** fix debounce ([f846c50](https://github.com/lewis6991/gitsigns.nvim/commit/f846c507242a74d9a458bff2d029bd2eae8c0ca1)), closes [#1046](https://github.com/lewis6991/gitsigns.nvim/issues/1046)


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
