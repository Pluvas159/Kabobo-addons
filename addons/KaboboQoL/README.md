# Kabobo's QoL

Small quality-of-life touches for **World of Warcraft: Forever**.

## Experience and reputation per hour

A faint line at the right end of the experience bar shows how fast you are levelling, and how long
until the next level:

```
12.3k xp/h  ·  42m to level
```

The reputation bar does the same for the faction you watch:

```
320 rep/h  ·  1h 10m to Honored
```

- Both use the **last 15 minutes**, so they follow what you are doing now: start grinding and the
  rate climbs; stop and it fades out. With no gains in the last 15 minutes the line disappears.
- Hover a bar for details: the rate over the last 15 minutes and over the whole session, how much
  you gained and in how long, and how much is left.
- A `/reload` keeps your session. Logging out for more than 15 minutes starts a new one, and so
  does watching a different faction (for its reputation).
- It adds text to Blizzard's own bars and changes nothing else, so they look and move as before
  (Edit Mode included).

## Commands

| | |
| --- | --- |
| `/kqol` | print your rates in chat |
| `/kqol xp` | experience line on or off |
| `/kqol rep` | reputation line on or off |
| `/kqol reset` | start counting from now |

## Changes

- 0.1.0: experience and reputation per hour, and the time to the next level or standing, on the
  status bars.
