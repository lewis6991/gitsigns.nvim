# Changelog

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
