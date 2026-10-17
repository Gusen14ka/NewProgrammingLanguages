import std/[locks, os, random, strformat]

const
  Sensors = 3
  BufSize = 3
  PerSensor = 6

type
  Reading = object
    sensor: int
    value: float

var
  buffer: array[BufSize, Reading]
  head, tail, count: int
  lock: Lock
  notFull, notEmpty: Cond
  sentSum, receivedSum: float
  sentCount, receivedCount: int
  waits: array[Sensors, int]

proc state(): string = &"buffer {count}/{BufSize}" & (if count == BufSize: " FULL" elif count == 0: " EMPTY" else: "")

proc put(r: Reading) =
  acquire(lock)
  while count == BufSize:
    inc waits[r.sensor]
    echo &"[sensor {r.sensor}] {state()} -> waiting..."
    wait(notFull, lock)
    echo &"[sensor {r.sensor}] woke up"
  buffer[tail] = r
  tail = (tail + 1) mod BufSize
  inc count
  inc sentCount
  sentSum += r.value
  echo &"[sensor {r.sensor}] put {r.value:5.1f}           {state()}"
  signal(notEmpty)
  release(lock)

proc take(): Reading =
  acquire(lock)
  while count == 0:
    echo &"[consumer]  {state()} -> waiting..."
    wait(notEmpty, lock)
  result = buffer[head]
  head = (head + 1) mod BufSize
  dec count
  inc receivedCount
  receivedSum += result.value
  echo &"[consumer]  took {result.value:5.1f} from sensor {result.sensor}   {state()}"
  signal(notFull)
  release(lock)

proc producer(id: int) {.thread.} =
  var rng = initRand(id + 1)
  let base = 20.0 + 10.0 * id.float
  for i in 1 .. PerSensor:
    put(Reading(sensor: id, value: base + rng.rand(-5.0 .. 5.0)))
    sleep(rng.rand(5 .. 15))

proc consumer() {.thread.} =
  var perSensor: array[Sensors, int]
  for n in 1 .. Sensors * PerSensor:
    let r = take()
    inc perSensor[r.sensor]
    sleep(40)
  echo "\n--- received per sensor ---"
  for id in 0 ..< Sensors:
    echo &"sensor {id}: {perSensor[id]} of {PerSensor}, waited on full buffer {waits[id]} times"

initLock(lock)
initCond(notFull)
initCond(notEmpty)

var producers: array[Sensors, Thread[int]]
var consumerThread: Thread[void]

createThread(consumerThread, consumer)
for id in 0 ..< Sensors:
  createThread(producers[id], producer, id)

joinThreads(producers)
joinThread(consumerThread)

echo "\n--- check ---"
echo &"produced: {sentCount}, consumed: {receivedCount}"
echo &"sum produced: {sentSum:.2f}, sum consumed: {receivedSum:.2f}"
echo(if sentCount == receivedCount and abs(sentSum - receivedSum) < 1e-6:
       "OK: no readings lost or duplicated"
     else: "ERROR: data mismatch")

deinitCond(notFull)
deinitCond(notEmpty)
deinitLock(lock)
