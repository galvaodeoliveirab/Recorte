# Recorte

App de captura de tela para macOS, feito em Swift/SwiftUI, inspirado no CleanShot X. Roda só no seu Mac, sem nuvem.

## Recursos

- **Captura de área, janela e tela inteira** com tela congelada, lupa de pixels e medidas em tempo real
- **Captura com rolagem**: junta automaticamente uma página longa enquanto você rola. Aguenta subir e descer, rolagem rápida demais e cabeçalhos/rodapés fixos (como barras de cookies)
- **Miniatura flutuante** (estilo Quick Access): copiar, salvar, editar, fixar, apagar ou **arrastar direto para outro app**
- **Editor de anotações**: seta, retângulo, elipse, linha, caneta, marca-texto, texto, borrar (pixelate) e contador numerado
- **Fixar na tela**: a captura fica numa janela por cima de tudo, com zoom por rolagem ou pinça
- **OCR**: copia o texto de qualquer área da tela (Vision, pt-BR + en-US)
- **Histórico** visual de capturas, temporizador e "esconder ícones da mesa"
- Toda captura é copiada automaticamente (PNG com DPI correto para telas Retina)

## Atalhos

| Atalho | Ação |
|---|---|
| ⌘⇧2 | Capturar área (Espaço alterna para janela) |
| ⌘⇧1 | Tela inteira |
| ⌘⇧8 | Janela |
| ⌘⇧0 | Captura com rolagem |
| ⌘⇧7 | Copiar texto (OCR) |
| ⌘⇧9 | Histórico |

## Como compilar

Requer macOS 14+ e Xcode/Swift 5.10+.

```bash
scripts/make-cert.sh        # uma vez: certificado local para a permissão de Gravação de Tela persistir
scripts/build.sh --install  # compila, assina e instala em /Applications
scripts/test-stitcher.sh imagem.png   # testes do algoritmo da captura com rolagem
```

## Tecnologias

ScreenCaptureKit · SwiftUI + AppKit · Vision (OCR) · Core Image · Carbon (atalhos globais) · Swift Package Manager
