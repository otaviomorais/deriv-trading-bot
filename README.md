# Deriv AI Trading Bot (Flutter APK)

Bot de trading para a corretora **Deriv** usando análise técnica + machine learning
(regressão logística online treinada em tempo real sobre ticks).

## Funcionalidades
- Conexão WebSocket direta com a API da Deriv
- Estratégia: retornos defasados + RSI + Bollinger + z-score de volatilidade alimentando um modelo ML que aprende continuamente a cada tick
- Contratos Rise/Fall (CALL/PUT) em índices sintéticos (Volatility 10–100)
- Gestão de risco: Stop Loss diário, Take Profit, limite de operações, pausa após 5 losses seguidos, martingale opcional (desativado por padrão)
- UI dark com saldo, PnL, sinal ao vivo e log de operações

## Como gerar o APK via GitHub Actions

1. Crie um repositório no GitHub (ex.: `deriv-trading-bot`).
2. Faça push deste projeto para a branch `main`:
   ```bash
   cd deriv_trading_bot
   git init
   git add .
   git commit -m "Bot Deriv AI inicial"
   git branch -M main
   git remote add origin https://github.com/SEU_USUARIO/deriv-trading-bot.git
   git push -u origin main
   ```
3. Vá na aba **Actions** do repositório → workflow *Build APK* → aguarde terminar.
4. Na execução concluída, baixe o artefato **deriv-trading-bot-apk** (app-release.apk).
5. Instale no Android (permita "instalar apps de fontes desconhecidas").

## Como usar o app
1. Crie um token de API:
   - **Token classico**: app.deriv.com -> Configuracoes -> **Token de API** (escopo leitura + escrita). Use App ID `1089`.
   - **Personal Access Token (`pat_...`)**: criado em api.deriv.com e vinculado a um aplicativo. Nesse caso informe o mesmo **App ID** do aplicativo nas configuracoes do bot.
2. Abra o app -> engrenagem -> cole o token + App ID, escolha simbolo, stake e sensibilidade.
3. Salve e toque em **INICIAR BOT**.

> Recomendação: teste primeiro em **conta DEMO** da Deriv (o token da demo funciona igual).

## Aviso de risco
Operações na Deriv envolvem risco elevado de perda. O modelo ML implementado é
educacional e não garante lucro. Use stop loss e comece com valores pequenos.
Este software é fornecido "como está", sem garantias.
