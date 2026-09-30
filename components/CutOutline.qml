import QtQuick
import QtQuick.Shapes

// Dashed outline around an item that was cut and is waiting to be pasted
Shape {
  id: outline

  property color color: "white"
  property real radius: 0
  property real inset: 1

  preferredRendererType: Shape.CurveRenderer

  ShapePath {
    strokeColor: outline.color
    strokeWidth: 1.5
    strokeStyle: ShapePath.DashLine
    dashPattern: [3, 3]
    fillColor: "transparent"

    PathRectangle {
      x: outline.inset
      y: outline.inset
      width: Math.max(0, outline.width - outline.inset * 2)
      height: Math.max(0, outline.height - outline.inset * 2)
      radius: outline.radius
    }
  }
}
