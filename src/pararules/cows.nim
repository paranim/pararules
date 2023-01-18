import std/tables

type
  CowTablePayload[K, V] = object
    counter: int
    data: Table[K, V]

  CowTable*[K, V] = object
    p: ptr CowTablePayload[K, V]

proc `=destroy`*[K, V](x: var CowTable[K, V]) =
  if x.p != nil:
    if x.p.counter == 0:
      when compileOption("threads"):
        deallocShared(x.p)
      else:
        dealloc(x.p)
    else:
      x.p.counter.dec

proc `=copy`*[K, V](a: var CowTable[K, V], b: CowTable[K, V]) =
  b.p.counter.inc
  `=destroy`(a)
  a.p = b.p

proc deepCopy*[K, V](y: CowTable[K, V]): CowTable[K, V] =
  when compileOption("threads"):
    result.p = cast[ptr CowTablePayload[K, V]](allocShared0(sizeof(CowTablePayload[K, V])))
  else:
    result.p = cast[ptr CowTablePayload[K, V]](alloc0(sizeof(CowTablePayload[K, V])))
  result.p.data = y.p.data

proc initCowTable*[K, V](): CowTable[K, V] =
  when compileOption("threads"):
    result.p = cast[ptr CowTablePayload[K, V]](allocShared0(sizeof(CowTablePayload[K, V])))
  else:
    result.p = cast[ptr CowTablePayload[K, V]](alloc0(sizeof(CowTablePayload[K, V])))
  result.p.data = initTable[K, V]()

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
