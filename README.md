# Shrb

Rubyで書かれたシェルです。
Bashの記法を出来るだけ再現するのが目標です。

Shell by Ruby.
The goal is to reproduce the notation of Bash as much as possible.

## 機能 / Features
- [x] コマンド実行
- [x] パイプ
- [x] 環境変数
- [x] 論理演算
- [x] コマンドのグループ化
- [ ] サブシェル
- [ ] 変数展開
- [x] デーモン化
- [x] 長い文字列をパイプすると標準入力で受け取れない
- [ ] ダブルクォート内の変数展開
- [ ] ダラー$後の変数展開
- [ ] 環境変数とインライン環境変数
- [ ] リダイレクト
  - [x] output
  - [x] appending output
  - [x] duplicating output
  - [x] input
  - [x] duplicating input
  - [ ] here document
  - [ ] open for reading and writing
- [ ] for
- [ ] while read
- [ ] ブレース展開
- [ ] プロセス置換


## インストール / Installation

    $ git clone https://github.com/booink/shrb

<!--
    $ gem install shrb
-->

## 使い方 / Usage

```sh
./exe/shrb
```

## コントリビュート / Contributing

バグ報告やプルリクエストは大歓迎です。このプロジェクトは安全で協力的なコラボレーションの場となることを目的としており、コントリビュータは [Contributor Covenant](http://contributor-covenant.org) をよく読んで守っていただけることを望んでいます。

Bug reports and pull requests are welcome. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## ライセンス / License
The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Shrb project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/booink/shrb/blob/master/CODE_OF_CONDUCT.md).
