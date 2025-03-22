# 第一阶段：使用 Node.js 镜像构建 Vue 应用
FROM docker.1ms.run/library/node:16.13.1-alpine AS build

# 设置工作目录
WORKDIR /app

# 定义构建参数，用于在构建时指定 VUE_APP_NETEASE_API_URL 的值
ARG VUE_APP_NETEASE_API_URL

# 使用构建参数设置环境变量，如果没有传递值，则使用默认值
ENV VUE_APP_NETEASE_API_URL=${VUE_APP_NETEASE_API_URL:-http://localhost:3000}

# 替换 Alpine Linux 的默认镜像源为清华大学镜像源
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories && \
    apk add --no-cache python3 make g++ git

# 安装依赖
COPY package.json yarn.lock ./
RUN yarn install

# 复制项目文件并构建 Vue 应用
COPY . .
RUN yarn config set electron_mirror https://npmmirror.com/mirrors/electron/ && \
    yarn build

# 动态生成 Nginx 配置文件
RUN echo "server {\n\
    gzip on;\n\
    listen       80;\n\
    listen  [::]:80;\n\
    server_name  localhost;\n\
\n\
    location / {\n\
        root      /usr/share/nginx/html;\n\
        index     index.html;\n\
        try_files \$uri \$uri/ /index.html;\n\
    }\n\
\n\
    location @rewrites {\n\
        rewrite ^(.*)\$ /index.html last;\n\
    }\n\
\n\
    location /api/ {\n\
        proxy_buffers           16 32k;\n\
        proxy_buffer_size       128k;\n\
        proxy_busy_buffers_size 128k;\n\
        proxy_set_header        Host \$host;\n\
        proxy_set_header        X-Real-IP \$remote_addr;\n\
        proxy_set_header        X-Forwarded-For \$remote_addr;\n\
        proxy_set_header        X-Forwarded-Host \$remote_addr;\n\
        proxy_set_header        X-NginX-Proxy true;\n\
        proxy_pass              ${VUE_APP_NETEASE_API_URL};\n\
    }\n\
}" > /app/nginx.conf

# 第二阶段：使用 Nginx 镜像部署应用
FROM docker.1ms.run/library/nginx:1.20.2-alpine AS app

# 替换 Alpine Linux 的默认镜像源为清华大学镜像源
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories

# 复制构建好的 Vue 应用到 Nginx 镜像的 /usr/share/nginx/html 目录
COPY --from=build /app/dist /usr/share/nginx/html

# 复制动态生成的 Nginx 配置文件到镜像中
COPY --from=build /app/nginx.conf /etc/nginx/conf.d/default.conf

# 安装 NeteaseCloudMusicApi（如果需要）
RUN apk add --no-cache nodejs npm && \
    npm install -g NeteaseCloudMusicApi

# 启动 Nginx 和 NeteaseCloudMusicApi
CMD ["sh", "-c", "if [ \"$VUE_APP_NETEASE_API_URL\" = \"http://localhost:3000\" ]; then npx NeteaseCloudMusicApi & fi && nginx -g 'daemon off;'"]
