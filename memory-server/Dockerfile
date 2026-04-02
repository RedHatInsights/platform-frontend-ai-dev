# Stage 1: Build the React dashboard
FROM registry.access.redhat.com/ubi9/nodejs-22:latest AS dashboard
USER 0
WORKDIR /app/dashboard
COPY dashboard/package.json dashboard/package-lock.json* ./
RUN npm ci
COPY dashboard/ .
RUN npm run build

# Stage 2: Python memory server
FROM registry.access.redhat.com/ubi9/python-312-minimal:latest
USER 0

RUN pip3 install uv

WORKDIR /app

COPY memory-server/pyproject.toml memory-server/uv.lock* ./
RUN uv sync --frozen --no-dev --no-install-project

COPY memory-server/src/ src/

# Copy dashboard build output into static dir
COPY --from=dashboard /app/memory-server/src/static/index.html src/static/index.html
COPY --from=dashboard /app/memory-server/src/static/assets/ src/static/assets/

RUN uv sync --frozen --no-dev

EXPOSE 8080

CMD ["uv", "run", "python", "-m", "src.server"]
