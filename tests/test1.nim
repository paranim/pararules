import unittest
import pararules
import macros

test "can iterate over fields":
  type
    TestObj = object
      x: int
      y: int
      name: string

  static:
    for sym in getType(TestObj)[2]:
      echo sym.symbol

  let o = TestObj(x: 0, y: 1, name: "")

  iterateFields(o)
  
  echo getFields[TestObj]()
