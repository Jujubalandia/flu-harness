# flu-harness

[🇺🇸 English](README.md) | **🇧🇷 Português**

Framework de desenvolvimento para publicar apps Flutter na App Store + Play Store em ≤20 dias.

Feito para o Claude Code, com um wizard de projeto, uma verificação de saúde de 26 itens e
quality gates que rodam nativamente em **PowerShell, CMD e Git Bash** no Windows.

Novo por aqui? [`docs/GETTING_STARTED.md`](docs/GETTING_STARTED.md) é o walkthrough
condensado de pasta vazia → app publicado. [`docs/WINDOWS.md`](docs/WINDOWS.md) é a
referência de shell, incluindo os quatro bugs de Windows que este harness existe para
evitar.

---

## O que é

Um conjunto de templates, skills e hooks que padronizam o fluxo completo:

```
Spec → UX → Dev → QA → Store → Marketing
```

O núcleo é `/flu-harness:new-flutter-project`: abra um diretório (novo ou
existente), digite o comando, e ele detecta a sua stack no `pubspec.yaml`,
configura o projeto e cria a estrutura completa: um `CLAUDE.md` preenchido,
`docs/`, git hooks do perfil de qualidade selecionado e knowledge rules
seletivas.

---

## Pré-requisitos

| Ferramenta | Versão mínima | Instalação |
|------|-------------|---------|
| Flutter | 3.35 stable | <https://docs.flutter.dev/install> |
| Dart | vem com o Flutter | — |
| Git | qualquer | <https://git-scm.com/downloads> |
| Claude Code | latest | `npm i -g @anthropic-ai/claude-code` |
| JDK | 17+ | o Android Studio já traz um |

No Windows, ative também o **Developer Mode** (o Flutter precisa de suporte a
symlink) e instale o **Git for Windows**: o `sh.exe` que vem com ele é o que
executa os git hooks:

```powershell
start ms-settings:developers
```

---

## Instalação

Instalado como plugin do Claude Code: os mesmos comandos em qualquer SO, sem
clone, sem shell script.

```
/plugin marketplace add Jujubalandia/flu-harness
/plugin install flu-harness@flu-harness
```

Skills, templates, scripts do doctor e perfis de hooks vêm dentro do plugin;
nada para colocar manualmente.

Atualize com `/plugin update flu-harness`, remova com
`/plugin uninstall flu-harness`.

### Standalone (opcional)

Se você quer o doctor e os runners de gates sem o Claude Code, existe um
instalador para cada shell. Eles produzem um layout idêntico.

```bash
# Git Bash / Linux / macOS
./scripts/install.sh                       # -> ~/.flu-harness
```

```powershell
# PowerShell
powershell -ExecutionPolicy Bypass -File scripts\install.ps1
```

```bat
rem cmd.exe
scripts\install.cmd
```

---

## Uso: novo projeto

```bash
mkdir ~/projects/my-app && cd ~/projects/my-app
claude
```

No Claude Code:

```
/flu-harness:new-flutter-project
```

### O que o wizard faz

**1. Detecta a stack automaticamente no `pubspec.yaml`** em 16 dimensões:

| Dimensão | O que detecta |
|-----------|----------------|
| Gerenciamento de estado | Riverpod · Bloc · Provider · GetX · Signals |
| Roteamento | go_router · auto_route · Beamer |
| Backend | Supabase · Firebase · Appwrite · Amplify |
| Banco de dados local | Drift · Isar · sqflite · Hive |
| Cliente HTTP | Dio · http · Chopper |
| Serialização | Freezed · json_serializable · built_value |
| Armazenamento seguro | flutter_secure_storage · shared_preferences (AVISO se guardar tokens) |
| i18n | gen-l10n oficial · easy_localization · slang |
| Animação | flutter_animate · Rive · Lottie |
| Monetização | RevenueCat · in_app_purchase · AdMob |
| Notificações | FCM · flutter_local_notifications |
| Testes | mocktail · mockito · Patrol · Alchemist |
| Lint | very_good_analysis · flutter_lints · dart_code_linter |
| Ferramentas de release | Shorebird · Fastlane |
| **Design system** | **`material_ui`/`cupertino_ui` vs in-framework: não são intercambiáveis** |
| Extras | camera · geolocator · share_plus · url_launcher · … |

Ele mostra a tabela e pede a sua confirmação antes de escrever qualquer coisa.

**2. Detecta o seu ambiente de shell** (quais dos três shells esta máquina consegue
rodar) e reporta o estado do seu Flutter SDK, incluindo o wrapper `sh` corrompido com
CRLF que vem na distribuição Windows (veja abaixo).

**3. Só pergunta o que não consegue detectar:** nome, org, descrição, idiomas,
monetização, perfil de hooks, editor, shell principal.

**4. Cria a estrutura:**
- `CLAUDE.md` preenchido (sem placeholders sobrando)
- `DECISIONS.md` + `TODO.md` inicializados
- `docs/` com os 6 templates de fase
- `.githooks/` com hooks **e um runner de gates para os três shells**
- `.claude/rules/` com knowledge rules **seletivas**, só para a stack detectada
- `.claude/settings.json` + hooks: a guarda contra operações destrutivas
- `.gitattributes` fixando LF para os hooks (não é cosmético no Windows)

**5. Prova que os três shells concordam** rodando o plano de gates em dry-run em cada
um, e depois imprime um checklist de próximos passos sob medida para a sua stack.

---

## A parte do Windows

Esta é a parte que mais difere de um harness típico, e não é enfeite. Cada um destes
itens foi descoberto rodando a coisa na prática.

### O Git executa os hooks por conta própria

No Windows, o Git for Windows executa os hooks pelo `sh.exe` que vem com ele, **não**
pelo shell em que você digitou `git commit`. Então `.githooks/pre-commit` é um único
script shell POSIX, e dispara de forma idêntica no PowerShell, no `cmd.exe` e no Git
Bash. O Git não consegue executar um `.ps1` ou um `.cmd` como hook, e é por isso que as
variantes Windows ao lado dele servem para rodar os mesmos gates na mão.

```
                        you type: git commit
                               │
              ┌────────────────┼────────────────┐
              ▼                ▼                ▼
         PowerShell         cmd.exe          Git Bash
              └────────────────┼────────────────┘
                               ▼
                    .githooks/pre-commit
                    run by Git for Windows' own sh.exe
                               │
                               ▼
                    .githooks/lib/quality.sh
                    (reads gates.def — one plan)
```

### Um plano de gates, três runners

Três shells significam três chances de divergir: alguém adiciona um gate ao runner
PowerShell, esquece o do batch, e um usuário Windows publica sem ele.

Então o plano é dado, não três cópias de código:

```
# .githooks/lib/gates.def
pre-commit=format,analyze,lint
pre-push=format,analyze,lint,test,build
```

`quality.sh`, `quality.ps1` e `quality.cmd` fazem parse do mesmo arquivo. O
`--dry-run` imprime o plano resolvido, e a suíte de testes garante que os três
produzem saída **idêntica** para todos os perfis, então eles não podem divergir em
silêncio.

### Quatro bugs que ele evita

| # | Bug | Sintoma | O que o flu-harness faz |
|---|-----|---------|-----------------------|
| 1 | `cmd.exe`: `shift` também move `%1` para `%0` | `%~dp0` deixa de significar "diretório deste script" e expande para `C:\project:C:\src\` | Captura `%~dp0` em uma variável na primeira linha, antes de qualquer parsing |
| 2 | `cmd.exe`: `set "VAR=value"` remove apenas as aspas externas | Um `""` aninhado sobrevive como dois caracteres de aspas literais e o argumento chega corrompido | Usa a forma simples `set VAR=value` para que as aspas internas sobrevivam intactas |
| 3 | O Flutter SDK traz `bin/internal/shared.sh` com CRLF | `internal/shared.sh: line 5: $'\r': command not found`, mas **só** no WSL ou em bash de Linux. O Git Bash roda o mesmo SDK sem problema. | Ramifica por `uname -s`: confia no wrapper sob MSYS, marca FAIL 26 no doctor só no shell POSIX onde ele realmente não roda, e imprime o comando de reparo |
| 4 | Um hook com CRLF no checkout | O Git procura um interpretador chamado `/bin/sh\r` e reporta algo sem relação nenhuma | `.gitattributes` fixa `eol=lf`, o instalador reescreve na instalação, e o FAIL 23 do doctor detecta isso |

Texto completo, com as evidências e os reparos: [`docs/WINDOWS.md`](docs/WINDOWS.md).

---

## flutter-doctor: verificação de saúde

26 verificações em qualquer projeto Flutter. Somente leitura: ele nunca edita os seus
arquivos.

```
/flu-harness:flutter-doctor
```

Ou rode direto. Escolha o seu shell:

```bash
sh ~/.flu-harness/scripts/doctor.sh                     # Git Bash, WSL, macOS, Linux
```

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.flu-harness\scripts\doctor.ps1"
```

```bat
%USERPROFILE%\.flu-harness\scripts\doctor.cmd
```

Adicione `--json` / `-Json` / `/json` para saída estruturada: o formato é verificado
pela suíte de testes, inclusive que todo FAIL carrega um `fix`.

### O que ele verifica

| Categoria | Verificações |
|----------|--------|
| Ambiente | flutter no PATH e reportando uma versão, ≥3.35, dart, git, Android SDK, JDK |
| Estrutura | `pubspec.yaml`, `CLAUDE.md`, `.claude/rules/`, `lib/`, `test/`, `analysis_options.yaml` |
| Dependências | `environment.sdk` fixado, `pubspec.lock` commitado, sem pacotes descontinuados, `l10n.yaml`, identificadores de loja |
| Segurança | `.git/`, `.gitignore` cobrindo Flutter + caminhos de segredos, nenhum segredo versionado, nenhuma credencial hardcoded |
| Gates | `core.hooksPath`, **fim de linha dos hooks**, biblioteca de gates completa para os três shells, `.gitattributes` |
| Windows | o wrapper `sh` do Flutter SDK corrompido por CRLF |

### Saída

```
  [OK]   flutter 3.41.6 on PATH (channel: stable)
  [OK]   Dart SDK version: 3.11.4 (stable) on "windows_x64"
  [OK]   flutter resolves to flutter.bat (the Windows entry point)
  [WARN] CLAUDE.md missing (flu-harness not initialized)
  [FAIL] CRLF line endings in hook script(s): pre-commit - git will refuse to run them
         fix: sed -i 's/\r$//' .githooks/pre-commit ; and add '.githooks/* text eol=lf' to .gitattributes
  ...
  OK: 19  WARN: 4  FAIL: 3  / 26 total
```

Código de saída `0` = nenhum FAIL. Código `1` = pelo menos um FAIL. Código `2` = uso
incorreto.

### Quando rodar

- D1, logo depois do wizard
- Depois de clonar em uma máquina nova
- Quando um hook falha sem um motivo claro, ou parece não rodar de jeito nenhum
- Quando algo funciona no Git Bash mas não no PowerShell
- Antes de qualquer build de release

---

## Quality gates

O pre-commit bloqueia conforme o **perfil ativo**:

| Profile | pre-commit | pre-push |
|---------|-----------|----------|
| `minimal` | `flutter analyze` | + `flutter test` |
| `standard` | `dart format` + `analyze` | + `lint` + `test` |
| `strict` *(padrão)* | `format` + `analyze` + `lint` | + `test` + `flutter build apk --debug` |

Gates:

| Gate | Comando |
|------|---------|
| `format` | `dart format --output=none --set-exit-if-changed .` |
| `analyze` | `flutter analyze --fatal-infos --fatal-warnings` |
| `lint` | métricas do `dart_code_linter` com `--set-exit-on-violation-level=warning` (ou `custom_lint`), pula sozinho quando não está configurado |
| `test` | `flutter test`, pula sozinho quando não existe `test/` |
| `build` | `flutter build apk --debug`, o único gate que pega uma falha do Gradle |

`strict` é o padrão por causa do `build`. O analyzer passar não significa que o app
compila para um alvo real, e descobrir isso no D16 em vez do D5 é a diferença entre
publicar ou não.

**Nunca enfraqueça um gate para fazê-lo passar.** Se a verificação está errada, corrija
a verificação no mesmo commit e diga por quê.

Prove que os seus três shells concordam, a qualquer momento:

```bash
sh  .githooks/lib/quality.sh  --dry-run
powershell -ExecutionPolicy Bypass -File .githooks\lib\quality.ps1 -DryRun
cmd /c .githooks\lib\quality.cmd /dry-run
```

---

## Variáveis de ambiente

| Variável | Efeito |
|----------|--------|
| `HARNESS_PROFILE` | `minimal` / `standard` / `strict` quando `.githooks/.profile` não existe |
| `HARNESS_DEVICE_OK` | `1` responde de antemão ao prompt "testado em um device real?" do pre-push |
| `HARNESS_SKIP_BUILD` | `1` pula o gate `build` e imprime um aviso bem visível de que pulou |
| `HARNESS_FLUTTER` / `HARNESS_DART` | apontam para um binário de SDK específico |

---

## Guarda contra operações destrutivas

Dois mecanismos bloqueiam operações irreversíveis antes que elas rodem.

### `.claude/settings.json`: denylist declarativa

```json
{ "permissions": { "deny": [
  "Bash(flutter pub publish*)",
  "Bash(fastlane deliver*)",
  "Bash(git push --force*)",
  "Bash(keytool -genkey*)",
  "Read(./android/key.properties)"
]}}
```

### `.claude/hooks/pre-tool-use.*`: bloqueio em runtime

Bloqueados: `flutter pub publish`, `dart pub publish`, `fastlane deliver|supply`,
`firebase appdistribution:distribute`, `firebase firestore:delete`,
`flutter build ipa`, `git push --force`, `git commit --no-verify`,
`git reset --hard`, `git clean -f`, `git filter-branch|filter-repo`,
`git rebase -i`, `rm -rf /` e `~`, `supabase db reset`, `DROP TABLE`,
`TRUNCATE TABLE`, `DELETE` sem `WHERE`, `keytool -genkey`.

Enviado para os três shells: `.sh` (sem dependência de Python), `.ps1`, `.cmd`.
A versão `.sh` evita `python3` de propósito, e é essa a razão pela qual a maioria dos
hooks não faz nada em silêncio numa máquina Windows.

---

## Knowledge rules

20 arquivos `.md` que o Claude carrega automaticamente com base nos arquivos que você
está editando. O wizard copia **apenas as relevantes para a stack detectada**.

| Rule | Copiada quando | Cobre |
|------|-------------|--------|
| `patterns.md` | sempre | estrutura de pastas, decomposição de widgets, estado assíncrono, streams |
| `performance.md` | sempre | `const`, escopo de rebuild, listas, imagens, isolates, tamanho do app |
| `security.md` | sempre | o que é seguro embutir, armazenamento seguro, assinatura, RLS |
| `accessibility.md` | sempre | semântica, alvos de 48dp, escala de texto, contraste, testes de a11y |
| `forbidden.md` | sempre | APIs deprecadas e removidas, além dos 13 padrões que causam bugs silenciosos |
| `testing.md` | sempre | fakes vs mocks, testes de widget, goldens, o que não testar |
| `riverpod.md` | State = Riverpod | providers, `watch`/`read`/`listen`, `AsyncValue`, testes |
| `bloc.md` | State = Bloc | eventos, segurança do `emit`, builder/listener/consumer, ownership |
| `go-router.md` | Roteamento = go_router | shell routes, redirects de auth, deep links, rotas tipadas |
| `dio.md` | HTTP = Dio | interceptors, refresh de token, cancelamento, falhas tipadas |
| `supabase.md` | Backend = Supabase | persistência de sessão em armazenamento seguro, RLS, armadilhas do `.single()` |
| `firebase.md` | Backend = Firebase | streams de auth, custo do Firestore, converters, rules |
| `drift.md` | DB = Drift | tabelas, migrations, isolate em background, queries reativas |
| `freezed.md` | Codegen | unions, JSON, a armadilha do `copyWith(null)`, valores de enum desconhecidos |
| `i18n.md` | i18n configurado | ARB, plurais ICU, armadilhas de locale do `Intl`, detecção de strings hardcoded |
| `revenue-cat.md` | Monetização | entitlements, restore, identidade do usuário, sandbox vs produção |
| `notifications.md` | Notificações | estados do FCM, a armadilha do `vm:entry-point`, canais, agendamento |
| `animation.md` | Animação | implícito vs explícito, ciclo de vida do controller, diagnóstico de jank |
| `material-ui.md` | Flutter 3.47+ | a divisão `material_ui`/`cupertino_ui` e a sua ponte de compatibilidade |

---

## Timeline de 20 dias

| Fase | Dias | Foco | Doc principal |
|-------|------|-------|----------|
| Spec + setup | D1-D3 | Especificação + ambiente rodando | `01-spec.md` |
| Core dev | D4-D10 | Features do MVP (1/dia) | `02-dev-plan.md` |
| Polish | D11-D13 | i18n, a11y, loading states, performance | `03-quality-gates.md` |
| QA + preparação da loja | D14-D15 | Build de release + assets | `04-testing.md`, `05-store-launch.md` |
| Submissão | D16-D17 | Upload do AAB/IPA + review | `05-store-launch.md` |
| Marketing | D18-D20 | Landing page + posts de lançamento | `06-marketing.md` |

> **Comece no D0 os relógios que não dá para acelerar.** A aprovação do Apple Developer
> leva dias, e uma **conta pessoal no Google Play precisa de 12 testadores inscritos por
> 14 dias corridos** antes de poder publicar em produção. São três semanas de
> antecedência: mais do que este plano inteiro. Suba um placeholder no teste fechado no
> D0. Veja `05-store-launch.md`.

---

## Matriz de devices

| Device | Plataforma | Uso |
|--------|----------|-----|
| Seu próprio celular Android | Android | loop principal: haptics, share sheet, deep links |
| Emulador Android | Android | iteração rápida, multi-usuário, tamanhos de tela |
| Appetize.io / Chrome | iOS / web | smoke semanal: layout, navegação, i18n |
| iPhone emprestado | iOS | TestFlight a partir do D17, 1-2 horas |

**Não tem Mac?** Um Mac na nuvem cobrado por hora para a etapa de archive, ou um runner
de CI que faz o archive e envia para o TestFlight. Os dois exigem uma conta Apple
Developer e uma chave de API do App Store Connect. Configure isso no **D1**, não no D16.

> **Ação do D1:** agende o empréstimo do iPhone para D17-D18. Registre no `TODO.md`.

---

## Estrutura do repo

```
flu-harness/
├── .claude-plugin/           plugin + marketplace manifests
├── .gitattributes            LF policy — load-bearing on Windows
├── docs/
│   ├── GETTING_STARTED.md
│   └── WINDOWS.md            the shell reference
├── scripts/
│   ├── quality.sh|ps1|cmd    gate runner, one per shell
│   ├── doctor.sh|ps1|cmd     26 checks
│   └── install.sh|ps1|cmd    standalone installer
├── git-hooks/
│   ├── pre-commit            POSIX sh — git runs this from any shell
│   ├── pre-push
│   ├── pre-commit.ps1|cmd    manual runners
│   ├── pre-push.ps1|cmd
│   └── profiles/<name>/gates.def
├── skills/
│   ├── new-flutter-project/
│   └── flutter-doctor/
├── templates/
│   ├── CLAUDE.md.tmpl
│   ├── DECISIONS.md.stub
│   ├── TODO.md.stub
│   ├── docs/                 6 phase templates
│   ├── rules/                20 knowledge rules
│   └── claude/               settings.json + pre-tool-use.*
└── tests/
    ├── test.sh                 suite: structure, shells, gates, guard, doctor
    ├── test.ps1                Windows suite, including real hook execution
    └── check_links.py          every relative doc link must resolve
```

---

## Contribuindo

1. Clone o repo e edite os arquivos localmente
2. Rode `bash tests/test.sh`: ele precisa terminar com 0 falhas. No Windows rode também
   `powershell -ExecutionPolicy Bypass -File tests\test.ps1`
3. Teste as skills contra o seu clone local:
   `/plugin marketplace add /path/to/local/flu-harness`
4. Faça commit e push

A suíte de testes garante que os três shells concordam no plano de gates, que a guarda
bloqueia e libera as coisas certas, que as 26 verificações do doctor estão presentes e
idênticas nas duas implementações nativas, e que os hooks estão em LF. Se você mudar um
gate ou uma verificação, são essas asserções que pegam a divergência.

Mudanças em templates e rules entram em vigor em projetos criados **depois** da mudança.
Projetos existentes não são afetados.

---

## FAQ

**Funciona no Windows?**
É para isso que ele foi projetado, em grande parte. Veja [`docs/WINDOWS.md`](docs/WINDOWS.md).

**Preciso do Git Bash instalado se eu uso PowerShell?**
Você precisa do **Git for Windows**, que traz o `sh.exe`: é esse o interpretador que o
git usa para rodar os hooks. Você nunca precisa abri-lo. Se você usa o Git Bash como
shell, ele já está lá.

**Por que o hook é um arquivo `.sh` se eu trabalho no PowerShell?**
Porque o git executa os hooks ele mesmo, pelo `sh.exe` que vem com ele, independente do
seu shell. Um `.ps1` não pode ser um git hook. Existem os gêmeos `.ps1` e `.cmd` para
rodar os mesmos gates na mão.

**Os três runners discordam. E agora?**
Eles não podem, por construção: eles fazem parse do mesmo `gates.def`. Se a saída do
`--dry-run` for diferente, o arquivo está corrompido ou um dos runners é uma cópia
desatualizada. Rode o wizard de novo.

**O `flutter` falha com `$'\r': command not found`. Por quê?**
O `bin/internal/shared.sh` do seu SDK tem fim de linha CRLF, um defeito da distribuição
Windows do SDK. Mas isso só quebra alguns shells: o Git Bash (MSYS) roda assim mesmo, o
WSL e o bash de Linux não. Então esse erro significa que você está no WSL, não no Git
Bash. Rode os gates pelo PowerShell ou pelo cmd, ou use o comando de reparo da
verificação 26 do doctor. Veja [`docs/WINDOWS.md`](docs/WINDOWS.md).

**Como começo sem sobrescrever arquivos existentes?**
O wizard verifica cada arquivo antes de criar. Os existentes são pulados com um aviso.

**Todas as 19 rules são sempre copiadas?**
Não: elas são seletivas. Um projeto sem Supabase nunca vê `supabase.md`. Para ter todas,
rode o wizard em um diretório sem `pubspec.yaml`.

**Como mudo o perfil de hooks?**
Rode `/flu-harness:new-flutter-project` de novo e escolha outro, ou substitua
`.githooks/lib/gates.def` e `.githooks/.profile` na mão.

**O doctor modifica arquivos?**
Não. Ele lê e reporta. As correções são sugeridas e aplicadas apenas quando você confirma.

**A saída `--json` é segura para CI?**
Sim. `tests/test.sh` garante que ela é parseável, que os números das verificações são
exatamente `1..26` sem lacunas nem duplicatas, e que todo `FAIL` tem um `fix` não vazio.

---

## Desinstalar

```
/plugin uninstall flu-harness
```

Remove o plugin. Projetos que você já gerou mantêm os seus arquivos: templates e rules
só valem para projetos criados depois de uma mudança.
