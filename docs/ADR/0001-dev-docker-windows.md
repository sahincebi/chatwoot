# ADR 0001: Dev Docker Windows

Status: Accepted
Date: 27.12.2025

## Context
Windows ortaminda Docker entrypoint script'leri CRLF line ending nedeniyle calismiyor ve postgres readiness kontrolu yanlis argumanlarla calisabiliyor. DB bootstrapping akisi da bu nedenle kesiliyor.

## Decision
Docker entrypoint ve helper script'leri icin LF line ending zorunlu tutulacak, entrypoint dosyalarinin executable olmasi garanti edilecek ve compose/.env ile Postgres-Redis ayarlari tutarli hale getirilecek.

## Consequences
- Windows kaynakli CRLF problemleri tekrarlanmaz.
- DB hazirlama akisi daha deterministik calisir.
- Repository'de line ending politikasi belirlenmis olur.

## Alternatives Considered
- .gitattributes kullanmadan manuel LF donusumu.
- Dockerfile icinde runtime LF donusumu.
