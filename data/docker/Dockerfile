# Aurora へ SQL を送るためのツールのコンテナ
# 手元に psql や session-manager-plugin を入れずに済むよう、必要なものをここにまとめる
#   psql                   : SQL の実行
#   AWS CLI v2             : SSM のセッション開始、Secrets Manager からの接続情報の取得
#   session-manager-plugin : AWS CLI の ssm start-session に必要
#   jq                     : シークレット (JSON) の解析
FROM public.ecr.aws/amazonlinux/amazonlinux:2023

RUN dnf install -y postgresql15 awscli-2 jq \
    && dnf clean all

# session-manager-plugin は CPU アーキテクチャごとに配布されている
RUN set -eux; \
    case "$(uname -m)" in \
      x86_64)  plugin_dir=linux_64bit ;; \
      aarch64) plugin_dir=linux_arm64 ;; \
      *) echo "未対応のアーキテクチャ: $(uname -m)" >&2; exit 1 ;; \
    esac; \
    dnf install -y "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/${plugin_dir}/session-manager-plugin.rpm"; \
    dnf clean all

COPY run.sh /usr/local/bin/run.sh
RUN chmod +x /usr/local/bin/run.sh

ENTRYPOINT ["/usr/local/bin/run.sh"]
