# Deriv AI Trading Bot (Flutter APK)

Bot de trading para a corretora **Deriv** usando análise técnica + machine learning
(regressão logística online treinada em tempo real sobre ticks).

> **v1.1:** migrado para a **nova plataforma de API da Deriv**
> ([developers.deriv.com](https://developers.deriv.com)) — tokens PAT (`pat_...`)
> + App ID registrado. A API legada (`ws.derivws.com` com app_id 1089) não aceita
> mais esse formato de token.

## Funcionalidades
- Autenticação na nova plataforma: REST (Bearer PAT) → OTP → WebSocket autenticado
- Estratégia: retornos defasados + RSI (Wilder) + Bollinger + z-score de
  volatilidade + momentum + MACD + ATR alimentando um modelo ML
  (regressão logística online com regularização L2) que aprende continuamente
  a cada tick
- Contratos Rise/Fall (CALL/PUT) em índices sintéticos (Volatility 10–100)
- Gestão de risco: Stop Loss diário, Take Profit, limite de operações,
  pausa após 5 losses seguidos, martingale opcional **com limite de níveis** (padrão: 3)
- Reconexão automática com backoff (preserva modelo e estatísticas)
- Modelo ML persistido em disco: sobrevive a reinícios do serviço/APP
  (`deriv_bot_model.json` no Download)
- Recuperação de contratos abertos ao reiniciar; venda a mercado no stop
- Token armazenado com segurança (Android Keystore via `flutter_secure_storage`)
- UI dark com saldo (DEMO/REAL), PnL, sinal ao vivo e log de operações

## Como gerar o APK via GitHub Actions

1. Crie um repositório no GitHub (ex.: `deriv-trading-bot`).
2. Faça push deste projeto para a branch `main`.
3. Vá na aba **Actions** do repositório → workflow *Build APK* → aguarde terminar.
4. Baixe o artefato **deriv-trading-bot-apk** (app-release.apk) e instale no Android.

## Como usar o app

### 1. Registre um app em developers.deriv.com (obrigatório)
1. Acesse [developers.deriv.com](https://developers.deriv.com) e faça login.
2. No Dashboard, registre um novo aplicativo do tipo **PAT**
   (Dashboard > Applications > Register new app).
3. Copie o **App ID** gerado (App IDs antigos, como o 1089, dão erro
   `Invalid application` na plataforma nova).

### 2. Gere seu token PAT
1. No mesmo Dashboard, vá em **API tokens** → crie um token (formato `pat_...`).
2. Marque os escopos **read** + **trade** (obrigatório para comprar contratos).
3. Copie e guarde — ele não pode ser visto novamente.

### 2.5 (Opcional) Teste a conexão pelo terminal antes de usar o app
Com o [Dart SDK](https://dart.dev/get-dart) instalado, na raiz do projeto:
```bash
dart run bin/diagnose.dart SEU_TOKEN_PAT SEU_APP_ID R_100
```
O diagnóstico percorre as mesmas etapas do app (contas → OTP → WebSocket →
balance/ticks/proposal) e mostra exatamente onde algo falha.

### 3. Configure o app
1. Abra o app → ícone de engrenagem.
2. Cole o **token PAT** e o **App ID**, escolha símbolo, stake, duração e sensibilidade.
3. Salve e toque em **INICIAR BOT**.

O bot conecta automaticamente na conta **DEMO** se houver mais de uma no token
(o tipo de conta aparece junto ao saldo).

## Arquitetura

```
lib/
├── services/deriv_api.dart    # REST (accounts+OTP) + WebSocket autenticado
├── bot/trading_bot.dart       # ciclo de vida, reconexão, gestão de risco
├── strategy/ml_strategy.dart  # regressão logística online
├── strategy/indicators.dart   # RSI Wilder, Bollinger, z-score
├── state/bot_state.dart       # estado global (Provider)
├── models/bot_config.dart     # configuração persistida
└── ui/                        # home + settings
```

## Como funciona a conexão (nova plataforma)

1. `GET /trading/v1/options/accounts` com headers `Authorization: Bearer <PAT>`
   e `Deriv-App-ID` → lista contas e escolhe a demo.
2. `POST /trading/v1/options/accounts/{id}/otp` → devolve uma URL de WebSocket
   já autenticada (OTP válido por 120s, uso único).
3. Conecta nessa URL e opera direto (`ticks`, `ticks_history`, `buy`,
   `proposal_open_contract`, `balance`, `sell`, `forget`).

## Aviso de risco

Operações na Deriv envolvem risco elevado de perda. O modelo ML implementado é
educacional: índices sintéticos são random walks por construção e nenhuma
estratégia garante lucro. Use stop loss, comece na DEMO e com valores pequenos.
Este software é fornecido "como está", sem garantias.
