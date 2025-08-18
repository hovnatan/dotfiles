FROM ubuntu:24.04

RUN yes | unminimize
RUN DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y git tzdata

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/