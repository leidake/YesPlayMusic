# --- 第一阶段：构建 ---
FROM node:16.13.1-alpine
ENV VUE_APP_NETEASE_API_URL=/api
WORKDIR /app

# 安装构建依赖，并配置 Git 使用 HTTPS 代替 SSH
# 注意：这里移除了 openssh-client
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories && \
    apk add --no-cache python3 make g++ git && \
    # --- 关键配置：强制 Git 使用 HTTPS ---
    git config --global url."https://github.com/".insteadOf "ssh://git@github.com/"

COPY package.json yarn.lock ./
# --- yarn install 现在应该可以成功了 ---
RUN yarn install

COPY . .
RUN yarn config set electron_mirror https://npmmirror.com/mirrors/electron/ && \
    yarn build

# --- 第二阶段：应用 ---
FROM nginx:1.20.2-alpine
ENV NETEASE_API_URL=""

COPY --from=0 /app/package.json /usr/local/lib/

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories && \
    apk add --no-cache --repository http://dl-cdn.alpinelinux.org/alpine/v3.14/main libuv && \
    apk add --no-cache --update-cache --repository http://dl-cdn.alpinelinux.org/alpine/v3.14/main nodejs npm

COPY --from=0 /app/docker/nginx.conf.example /etc/nginx/conf.d/default.conf.template
COPY --from=0 /app/dist /usr/share/nginx/html

# ... (FROM nginx 和后续指令保持不变)
# 创建启动脚本，根据环境变量决定是否安装API并配置nginx
RUN echo '#!/bin/sh' > /start.sh \
 && echo 'set -e' >> /start.sh \
 && echo '' >> /start.sh \
 && echo 'if [ -z "$NETEASE_API_URL" ]; then' >> /start.sh \
 && echo '  # 未设置API URL，安装NeteaseCloudMusicApi，使用本地API' >> /start.sh \
 && echo '  echo "No NETEASE_API_URL provided, installing NeteaseCloudMusicApi..."' >> /start.sh \
 && echo '  # 使用更安全的方式解析package.json获取版本号' >> /start.sh \
 && echo '  API_VERSION=$(grep -o \"NeteaseCloudMusicApi\\": \\\"[^\\\"]*\\\" /usr/local/lib/package.json | cut -d':' -f2 | tr -d ' \",')' >> /start.sh \
 && echo '  npm i -g NeteaseCloudMusicApi@$API_VERSION' >> /start.sh \
 && echo '  # 使用本地API地址' >> /start.sh \
 && echo '  API_URL=http://localhost:3000/' >> /start.sh \
 && echo 'else' >> /start.sh \
 && echo '  # 设置了API URL，不安装NeteaseCloudMusicApi，使用外部API' >> /start.sh \
 && echo '  echo "Using external NETEASE_API_URL: $NETEASE_API_URL"' >> /start.sh \
 && echo '  API_URL=$NETEASE_API_URL' >> /start.sh \
 && echo 'fi' >> /start.sh \
 && echo '' >> /start.sh \
 && echo '# 配置nginx，替换proxy_pass' >> /start.sh \
 && echo 'sed "s|http://localhost:3000/|$API_URL|g" /etc/nginx/conf.d/default.conf.template > /etc/nginx/conf.d/default.conf' >> /start.sh \
 && echo '' >> /start.sh \
 && echo '# 启动nginx' >> /start.sh \
 && echo 'nginx' >> /start.sh \
 && echo '' >> /start.sh \
 && echo '# 如果使用本地API，启动NeteaseCloudMusicApi' >> /start.sh \
 && echo 'if [ -z "$NETEASE_API_URL" ]; then' >> /start.sh \
 && echo '  exec npx NeteaseCloudMusicApi' >> /start.sh \
 && echo 'else' >> /start.sh \
 && echo '  # 使用外部API，保持容器运行' >> /start.sh \
 && echo '  tail -f /dev/null' >> /start.sh \
 && echo 'fi' >> /start.sh \
 && chmod +x /start.sh

CMD ["sh", "/start.sh"]
