import std/tables

type
  CowTablePayload[K, V] = ref object
    counter: int
    data: Table[K, V]

  CowTable*[K, V] = object
    p: CowTablePayload[K, V]

proc `=destroy`*[K, V](x: var CowTable[K, V]) =
  if x.p != nil:
    if x.p.counter == 0:
      `=destroy`(x.p)
    else:
      x.p.counter.dec

proc `=copy`*[K, V](a: var CowTable[K, V], b: CowTable[K, V]) =
  b.p.counter.inc
  `=destroy`(a)
  a.p = b.p

proc deepCopy*[K, V](y: CowTable[K, V]): CowTable[K, V] =
  result.p = CowTablePayload[K, V](
    counter: 0,
    data: y.p.data
  )

proc initCowTable*[K, V](): CowTable[K, V] =
  result.p = CowTablePayload[K, V](
    counter: 0,
    data: initTable[K, V]()
  )

proc hasKey*[K, V](t: CowTable[K, V], key: K): bool =
  t.p.data.hasKey(key)

proc `[]`*[K, V](t: CowTable[K, V], key: K): V =
  t.p.data[key]

proc `[]=`*[K, V](t: var CowTable[K, V], key: K, val: V) =
  if t.p.counter > 0:
    t = t.deepCopy
  t.p.data[key] = val

proc del*[K, V](t: var CowTable[K, V], key: K) =
  if t.p.counter > 0:
    t = t.deepCopy
  t.p.data.del(key)

iterator pairs*[K, V](t: CowTable[K, V]): (K, V) =
  for x in t.p.data.pairs:
    yield x

iterator values*[K, V](t: CowTable[K, V]): V =
  for x in t.p.data.values:
    yield x
