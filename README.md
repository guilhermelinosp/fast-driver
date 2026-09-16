# Fast Driver

[![CI](https://github.com/guilhermelinosp/fast-driver/actions/workflows/pipeline.yml/badge.svg)](https://github.com/guilhermelinosp/fast-driver/actions/workflows/pipeline.yml)

Vertical slice independente em Flutter para um Driver receber e aceitar
corridas. A UI usa `StatefulWidget`/`setState`; os serviços e receivers são
interfaces/injetáveis para testes.

O fluxo principal recebe ofertas por uma abstração compatível com um gateway
APNs/FCM. Não há plugin, credenciais ou projeto Firebase/APNs neste repositório:
o default atual é um receiver no-op.

## Contrato backend real

- `POST {baseUrl}/api/v1/drives/{rideId}/accept`
- O contrato desejado `/rides/{rideId}/accept` ainda não existe e não é usado.
- Sem body; envia body vazio e `Content-Type: application/json`.
- Header obrigatório: `driver_id: <UUID>`.
- Sucesso: HTTP `201`, JSON `{"id":"rideId"}`.
- Conflito: HTTP `409` com `error.code = RIDE_ALREADY_ACCEPTED`.
- Outros erros preservam `error.code`, `error.message` e `requestId` na UI.

## Contrato de push de ofertas

O gateway deve entregar ao plugin uma notificação que o adaptador normalize para
`PushNotification`:

```json
{
  "type": "ride.requested.v1",
  "data": {
    "id": "ride-123",
    "rider_id": "rider-456",
    "pickup_latitude": -23.55,
    "pickup_longitude": -46.63,
    "destination_latitude": -23.56,
    "destination_longitude": -46.65
  }
}
```

`data` também pode ser uma string JSON. O `messageId` do provedor (FCM
message ID ou APNs `apns-id`) deve ser passado separadamente quando disponível.
O adaptador aceita `event`/`event_type` como alias de `type` e `payload` como
alias de `data`.

Somente `ride.requested.v1` é transformado em `RideOffer`. Payload inválido ou
evento desconhecido é descartado sem interromper o receiver. O plugin futuro é
responsável por traduzir callbacks de APNs/FCM para `PushNotificationReceiver`;
essa integração está pendente.

O receiver recebe o `driver_id` antes de iniciar:

```dart
final source = PushRideOffersService(receiver: providerPushReceiver);
await source.start(driverId: driverId);
source.offers.listen(showOffer);
```

O `driver_id` é um UUID v4 criado uma única vez na instalação e persistido com
`shared_preferences`. Ele deve ser associado ao registro/token do provedor pelo
adaptador futuro; nenhuma chave, token ou segredo é armazenado neste projeto.

## UI e execução

A tela principal permanece branca e minimalista, sem lista de cards. Cada oferta
abre um popup com Ride ID, coordenadas e `Aceitar`/`Recusar`. Ofertas recebidas
com outro popup aberto ficam enfileiradas; duplicatas da mesma ride são
ignoradas. `Recusar` oculta a ride localmente. `Aceitar` usa o
`AcceptRideService` com o `driver_id` persistido.

O app suporta somente Android e iOS. Por padrão, `ApiConfig` usa
`http://localhost:8080` no iOS Simulator e `http://10.0.2.2:8080` no Android
Emulator. Sobrescreva com `--dart-define=API_BASE_URL=...`.

```bash
flutter pub get
flutter run -d <ios-simulator-id>
```

## Integração pendente do provedor

Ainda é necessário escolher/configurar o provedor, solicitar permissões, obter
tokens, registrar o token no gateway e ligar callbacks do plugin ao
`PushNotificationReceiver`. Variáveis esperadas nessa integração, fora deste
repositório, são `API_BASE_URL`, `FCM_PROJECT_ID`/credenciais FCM e
`APNS_BUNDLE_ID`/credenciais APNs. Segredos nunca devem ser commitados.

## Testes e qualidade

```bash
dart format .
flutter analyze
flutter test
```

Os testes cobrem identidade UUID persistida, normalização de payload APNs/FCM,
parsing de payload push válido/malformado de `ride.requested.v1`, eventos
desconhecidos, dedupe, fila, abertura do popup, aceitar/recusar e o contrato
HTTP de aceite.

## Limitações

- Não há autenticação, matching, plugin push ou execução em background.
- O app não altera nem adapta o backend.
- O backend local deve aceitar conexões do endereço escolhido para simuladores
  e dispositivos físicos.

## Configuração local via .env

Copie `.env.example` para `.env` e preencha **todos** os valores (obrigatórios):

```bash
cp .env.example .env
flutter run --dart-define-from-file=.env
```

| Variável | Descrição |
| --- | --- |
| `API_BASE_URL` | URL base do backend (contrato `POST /api/v1/drives/{rideId}/accept`) |

Sem `API_BASE_URL` o app não inicia (`ApiConfig.validate()` lança erro).
