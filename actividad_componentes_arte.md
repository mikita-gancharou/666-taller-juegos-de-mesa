# 666 — Actividad: Componentes, Interfaz y Arte
**Taller de Juegos de Mesa — Image Campus**
*A strategy game of cards and dices*

---

## 1. LISTADO TOTAL DE COMPONENTES

### 1.1 Preguntas guía

> **¿Qué componentes tengo? ¿Cuántos hay? ¿Cómo son y qué estructura tienen?**

Configuración base asumida: **2–4 jugadores, 15–25 min**.

### 1.2 Tabla maestra de componentes

| # | Componente | Cant. | Formato / Medida | Material / Acabado | Función en el juego |
|---|---|---|---|---|---|
| 1 | Cartas de juego | **60** | 63 × 88 mm (poker) | 300 gsm, lino, dorso opaco | Mazo principal + mercado |
| 2 | Cartas instantáneas | **6** | 63 × 88 mm | Igual + **borde doble** y canto rojo | Se disparan al aparecer |
| 3 | Dados de jugador | **12** (3 × jugador) | d6 de 16 mm | Resina, puntos grabados y pintados, 4 colores | Estado del jugador (3-3-3 → 6-6-6) |
| 4 | Dado del destino | **1** | d6 de 19 mm (más grande) | Negro / rojo, distinto al resto | Orden de turno, GAMBLE, REROLL |
| 5 | Sellos de bloqueo | **12** (3 × jugador) | Ficha Ø 22 mm | Cartón 2 mm troquelado | Marcan un 6 "lockeado" |
| 6 | Fichas de escudo | **6** | Ficha Ø 22 mm, forma distinta (escudo) | Cartón 2 mm | SHIELD activo sobre un dado |
| 7 | Tableros de jugador | **4** | 180 × 90 mm | Cartón 1,5 mm, **con hueco para los 3 dados** | Interfaz: dados + track de momentum |
| 8 | Tapete del mercado | **1** | 300 × 120 mm | Cartón o tela | Mazo + 3 slots + descarte |
| 9 | Reglamento | **1** | A5, 8 págs. | Papel 130 gsm | — |
| 10 | Caja | **1** | 140 × 100 × 65 mm | Cartón rígido | — |

**TOTAL DE PIEZAS: 103** (66 cartas + 13 dados + 18 fichas + 4 tableros de jugador + tapete + reglamento), sin contar la caja.

> **Detalle temático:** 13 dados y 66 cartas.

### 1.3 Estructura del mazo (66 cartas)

| Tipo | Cant. | Efecto | Objetivo |
|---|---|---|---|
| **Movimiento +1** | 14 | Sube 1 un dado | Propio u oponente |
| **Movimiento +2** | 10 | Sube 2 un dado | Propio u oponente |
| **Movimiento −2** | 6 | Baja 2 un dado | Propio u oponente |
| **Dual** | 6 | Dos efectos a la vez (ej. +2 propio / −1 rival) | Ambos |
| **SHIELD** | 6 | Protege un 6 propio del próximo SMASH/TRADE | Propio |
| **SMASH** | 5 | Baja 2 un 6 rival | Oponente |
| **TRADE** | 5 | Baja 2 un 6 rival, luego baja 1 uno propio | Ambos |
| **GAMBLE** | 4 | Tira d6: 1-3 baja 1 / 4-6 sube 2 | Propio |
| **REROLL** | 4 | Un dado pasa a valor aleatorio | Cualquiera |
| — subtotal — | **60** | | |
| **SURGE** *(instant)* | 2 | Todos los dados +1 | Todos |
| **COLLAPSE** *(instant)* | 2 | Todos los dados no bloqueados −1 | Todos |
| **FLOOD** *(instant)* | 2 | Descartar el mercado, repartir 3 nuevas | Mercado |
| **TOTAL** | **66** | | |

**Ratio de agresión: 28 cartas de 66 — el 42 % puede dañar a un rival** (−2, Dual, SMASH, TRADE, REROLL, COLLAPSE). Cuatro de cada diez. Es el dato que después justifica la elección estética.

**Balance de progreso (chequeo rápido):** cada jugador necesita subir 9 pips (3-3-3 → 6-6-6). Las 24 cartas constructivas aportan 34 pips en total, más SURGE y GAMBLE. Con 4 jugadores hacen falta 36 pips y hay ~40 disponibles: el margen es mínimo, así que **el reglamento tiene que decir que se rebaraja el descarte** cuando el mazo se agota, o la partida se traba.

### 1.4 Anatomía de la carta (interfaz)

```
┌───────────────────────────┐
│ ①  ────── NOMBRE ──────── │   ① Banda de nombre + color de familia
│                           │
│                           │
│        ②  ICONO           │   ② Icono grande (60 % del alto) — se lee
│         GRANDE            │      desde el otro lado de la mesa
│                           │
│                           │
│ ③ ▲▲ +2   →  ④ [ TÚ|RIVAL ]│  ③ Valor numérico + flecha de dirección
│                           │   ④ Banda de objetivo (a quién afecta)
│ ⑤ texto de recordatorio   │   ⑤ Texto sólo si el icono no alcanza
└───────────────────────────┘
```

**Sistema de iconos (6 familias, 6 colores):**

| Familia | Icono | Color |
|---|---|---|
| Subir | Flecha ▲ con cuernos | Amarillo azufre |
| Bajar | Flecha ▼ con tridente | Violeta |
| Ataque (SMASH/TRADE) | Puño / calavera partiendo un dado | Rojo |
| Defensa (SHIELD) | Pentagrama-escudo | Cian |
| Azar (GAMBLE/REROLL) | Dado en movimiento | Magenta |
| Instantánea | **Doble borde + rayo** | Rojo sobre negro |

**Reglas de legibilidad:**
- Icono legible a **1 metro** — es la distancia real de lectura del mercado.
- **Codificación redundante**: color + forma de icono + posición. Nunca sólo color (≈8 % de los jugadores tiene daltonismo; un juego de rojo/verde infernal es la trampa clásica).
- Las 3 cartas del mercado están boca arriba todo el tiempo, así que el icono importa más que la ilustración.

### 1.5 Anatomía del tableros de jugador

```
┌──────────────────────────────────────────────┐
│  JUGADOR                                     │
│   ╭────╮   ╭────╮   ╭────╮                   │  huecos físicos para
│   │ ⚄  │   │ ⚄  │   │ ⚄  │   ← 3 dados       │  que el dado no se
│   ╰────╯   ╰────╯   ╰────╯                   │  mueva de valor sin
│    [sello] [sello] [sello]  ← slots de lock  │  querer
│                                              │
│  MOMENTUM   0🔒→2 acc.  1🔒→3  2🔒→4          │  track impreso
└──────────────────────────────────────────────┘
```

El track de momentum va **impreso** en el tablero: no necesita componente extra, se lee contando los sellos.

### 1.6 Huecos de reglas detectados (afectan al arte)

Cosas que el reglamento actual no cierra y que **el diseño gráfico tiene que resolver o el reglamento aclarar**:

1. **Nº de jugadores** no está declarado en el deck. Define la cantidad de dados y de tableros → hay que fijarlo antes de presupuestar.
2. **"Lock" no está definido formalmente.** Por SMASH/TRADE se deduce que un 6 bloqueado *sigue siendo atacable*. La interfaz debe comunicar "bloqueado ≠ seguro" — por eso el sello es una ficha *encima*, no un cambio de estado del dado.
3. **El track de momentum sólo llega a 2 bloqueados** (con 3 ganás). Correcto, pero el tablero debe cerrarlo visualmente para que nadie busque la fila "3".
4. **Overflow**: "+2 sobre un 5" → ¿queda en 6 o no se puede jugar? El icono de flecha debe llevar un tope visual (una barra en el 6) para volverlo obvio.
5. **SURGE (+1 a todos) vs. dados bloqueados**: COLLAPSE dice explícitamente "no bloqueados", SURGE no dice nada. Si SURGE afecta a los bloqueados, no pasa nada (tope en 6). Conviene escribirlo igual.
6. **Cartas Dual**: son el problema de layout más difícil del mazo — dos efectos, dos objetivos, una carta. Solución propuesta: **partir la carta en diagonal**, mitad superior "TÚ", mitad inferior "RIVAL", cada una con su icono.

---

## 2. LOS DOS MOODBOARDS

### MOODBOARD A — "GRIMORIO"
*Grabado ocultista, siglo XVII*

**Concepto en una frase:** el juego es una página arrancada de un manual de demonología.

| | |
|---|---|
| **Paleta** | Negro humo `#0B0A0A` · Pergamino `#E8DCC0` · Rojo sangre seca `#8B1A1A` · Oro viejo `#C9A227` · Verde ceniza `#4A5240` |
| **Técnica** | Xilografía / grabado a buril, tramado cruzado (cross-hatching), sin degradados, mancha de papel |
| **Tipografía** | Blackletter para títulos · **Century Schoolbook** para cuerpo (ya está en el deck del juego) |
| **Iconografía** | Sigilos de la Ars Goetia, diagramas alquímicos, sellos de lacre, círculos de invocación, memento mori |
| **Referentes visuales** | Dictionnaire Infernal (Collin de Plancy) · Grabados de Durero · Gustave Doré · El Bosco · Tarot de Marsella |
| **Referente de juego** | *Escape the Dark Castle* |
| **Tono** | Solemne, austero, "premium", adulto |

**Búsquedas para Pinterest (copiar y pegar):**
```
medieval woodcut engraving   ·   ars goetia sigil   ·   alchemical diagram
grimoire manuscript page     ·   Dürer engraving    ·   tarot de marseille
wax seal red                 ·   occult symbols     ·   blackletter type
memento mori woodcut         ·   cross hatching illustration
```

---

### MOODBOARD B — "NEÓN INFERNAL"
*Cartoon pop, sticker de skate, 90s*

**Concepto en una frase:** el diablo dibujado, no el diablo temible.

| | |
|---|---|
| **Paleta** | Negro tinta `#101018` · Rojo diablo `#FF2D2D` · Magenta neón `#FF2E88` · Amarillo azufre `#FFD400` · Violeta `#6B2BD9` · Cian veneno `#00E5C0` |
| **Técnica** | Contorno grueso y variable, colores planos, halftone/trama de puntos, sin realismo |
| **Tipografía** | Display pesada e inclinada tipo lettering de hot-rod, con sombra dura y contorno |
| **Iconografía** | Diablitos rubber-hose, tridentes, llamas, dados con cara, calaveras sonrientes, manitos de guante |
| **Referentes visuales** | Cuphead · Rat Fink / Ed Roth · Vince Ray & lowbrow art · tapas de heavy metal ochentoso · carteles de lucha libre · cajas de fósforos vintage con diablo |
| **Referentes de juego** | *The Binding of Isaac: Four Souls* · *King of Tokyo* |
| **Tono** | Cómico, agresivo, ruidoso, "family-friendly satánico" |

**Búsquedas para Pinterest (copiar y pegar):**
```
rubber hose cartoon devil    ·   90s skate sticker art   ·   halftone comic devil
hot rod flames lettering     ·   cuphead style character ·   Rat Fink Ed Roth
vintage matchbox devil label ·   lucha libre poster      ·   lowbrow art devil
adult swim bumper art        ·   neon sign devil
```

---

### 2.1 Cómo armar cada moodboard (grilla sugerida, 15 min por board)

Canva → lienzo **1920 × 1080 px**, grilla de 4 × 3 = **12 celdas**:

| Fila | Contenido | Celdas |
|---|---|---|
| 1 | **Ambiente general** — 4 imágenes de mundo/atmósfera | 4 |
| 2 | Personaje/criatura (1) · Textura (1) · Tipografía (1) · Iconos (1) | 4 |
| 3 | Tira de paleta con hex (1 celda ancha) · 2 referentes de juego reales (fotos de componentes) | 3 |

Regla: **cada imagen tiene que justificar una decisión de producción concreta** (un color, un trazo, una tipografía, un acabado). Si una imagen es "linda pero no decide nada", afuera.

---

## 3. CINCO JUEGOS CON ESTÉTICA SIMILAR (BGG)

| # | Juego | Año | Por qué sirve como referencia |
|---|---|---|---|
| 1 | **The Binding of Isaac: Four Souls** | 2018 | Iconografía satánica en clave cartoon, cartas con d6 y *take-that* directo. Lo concreto: cómo el dorso y el borde de carta distinguen el tipo antes de leer el texto. |
| 2 | **King of Tokyo** | 2011 | Dados, cartas y agresión entre jugadores. Lo concreto: iconos grandes y color por función, para que el estado de cada jugador se lea desde cualquier asiento — el mismo problema que nuestras 3 cartas de mercado boca arriba. |
| 3 | **Dice Throne** | 2018 | Lo concreto: el tablero de jugador con huecos para los dados y el track de estado impreso al lado. Es exactamente el layout que tenemos que resolver. |
| 4 | **Blood on the Clocktower** | 2022 | Lo concreto: el Grimorio del narrador es un libro físico con fichas de personaje, y cada ficha comunica por ilustración y forma, no por texto. Referencia para nuestros sellos de bloqueo y fichas de escudo, y para el concepto del Moodboard A. |
| 5 | **Escape the Dark Castle** | 2017 | Lo concreto: blanco y negro, grabado, un único color de acento en toda la caja. Prueba de que la vía austera del Moodboard A funciona comercialmente. |

**Alternativas si hace falta ampliar:** *Gloom* (cartoon oscuro a lo Edward Gorey), *Boss Monster* (el jugador es el malo), *Munchkin* (humor y traición), *Machi Koro* (mercado de 3 cartas boca arriba con dados).

---

## 4. MOODBOARD ELEGIDO: **B — "NEÓN INFERNAL"**

### 4.1 Argumentación (esto es lo que se defiende en la presentación)

1. **El arte suaviza la agresión.** El 42 % del mazo sirve para arruinarle el turno al de al lado. Con estética solemne, bajarle el 6 a un amigo se siente hostil; con estética cartoon, se lee como un chiste.
2. **Legibilidad del mercado.** Hay 3 cartas boca arriba que todos leen desde su asiento. Contorno grueso + color plano + alto contraste se lee a 1 m; el tramado de grabado se empasta.
3. **Las instantáneas deben ser llamativas.** Una carta que se dispara sola al aparecer tiene que distinguirse de inmediato. Un borde doble de neón sobre negro se ve a la primera; un marco grabado, no.
4. **Los dados son la estrella y viven entre 3 y 6.** El número tiene que leerse siempre. La vía cartoon permite pips gigantes y codificación por color; la vía grabado empuja a dados "bonitos" e ilegibles.
5. **Posicionamiento comercial.** Es un juego corto, de 20 minutos. El grabado negro y oro aparenta un euro de 50 € y genera la expectativa equivocada en la góndola. El neón anticipa lo que el juego realmente es.
6. **Producción.** Colores planos = menos costo de prueba de color, mejor tolerancia a variación de imprenta, escalable a merch y a expansiones.

### 4.2 Qué nos llevamos del Moodboard A (injertos)

No se descarta entero — se le roban tres cosas:

- **El dorso de las cartas**: un sigilo de la Ars Goetia, en rojo sobre negro, geométrico. Da profundidad y hace que el mazo boca abajo se vea serio.
- **El "666" del logo**: construido como un sello de invocación circular, no como lettering cartoon. Contraste entre marca solemne y contenido gamberro.
- **Century Schoolbook** para el texto de reglas y de recordatorio en carta: es la tipografía que ya usa el deck, tiene autoridad y es más legible en cuerpo chico que cualquier display.

### 4.3 Próximos pasos

- [ ] Cerrar el número de jugadores (2–4 vs. 2–6) → congela cantidad de dados, tableros y sellos.
- [ ] Bocetar las 6 familias de iconos en blanco y negro. **Test: identificar la familia a 1 m sin color.**
- [ ] Resolver el layout de la carta Dual (corte en diagonal).
- [ ] Prototipo en papel del tablero de jugador con los 3 huecos de dado.
- [ ] Test de daltonismo: pasar la paleta por un simulador de deuteranopía.
