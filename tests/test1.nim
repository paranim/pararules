import unittest
import pararules

test "can iterate over fields":
  type
    TestObj = object
      x: int
      y: int
      name: string

  let t = (x: 0, y: 1, name: "")
  let o = TestObj(x: 0, y: 1, name: "")

  iterateFields(t)
  iterateFields(o)
