import unittest
import pararules

test "can create session":
  var session = Session[string]()
  var node = AlphaNode[string]()
  node.testField = Field.Attribute
  node.testValue = "color"
  session.rootNode.children.add(node)
  echo session
