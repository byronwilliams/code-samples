#!/usr/bin/env python

def indexOf(xs,y):
  try:
    result = xs.index(y)
  except:
    result = -1
  return result

def lastIndexOf(xs,y):
  xs.reverse()

  try:
    result = len(xs)-1-xs.index(y)
  except:
    result = -1

  xs.reverse()

  return result

class Grid:
  def __init__(self,selector,x_size,y_size):
    self.selector = selector
    self.x_size = x_size
    self.y_size = y_size
    self.create_grid(x_size,y_size)

  def create_grid(self,x_size,y_size):
    self.grid = []

    for y in range(y_size):
      row = [None for x in range(x_size)]
      self.grid.append(row)

  def push_left(self,row,piece):
    xrow = self.grid[row]

    if not self.is_row_blocked(xrow):
      firstEmpty = indexOf(xrow,None)
      lastEmpty  = lastIndexOf(xrow,None)

      if firstEmpty == 0:
        xrow.pop(firstEmpty)
        xrow.insert(firstEmpty, piece)
      else:
        xrow.pop(lastEmpty)
        xrow.insert(0,piece)

  def push_right(self,row,piece):
    xrow = self.grid[row]
    if not self.is_row_blocked(xrow):
      lastEmpty = lastIndexOf(xrow,None)
      xrow.pop(lastEmpty)
      xrow.append(piece)

  def push_top(self,col,piece):
    xcol = [self.grid[row][col] for row in range(self.y_size)]
    print(xcol)
    firstEmpty = indexOf(xcol,None)
    lastEmpty  = lastIndexOf(xcol,None)

    xcol.insert(firstEmpty,piece)
    xcol.pop(lastEmpty)
    print(xcol)
    for row in range(self.y_size):
      self.grid[row][col] = xcol[row]

  def push_bottom(self,col,piece):
    xcol = [self.grid[row][col] for row in range(self.y_size)]
    lastEmpty = lastIndexOf(xcol,None)
    xcol.pop(lastEmpty)
    xcol.append(piece)


    for row in range(self.y_size):
      self.grid[row][col] = xcol[row]

  def is_row_blocked(self,row):
    return row.count(None) == 0

  def is_col_blocked(self,col):
    return [self.grid[row][col] for row in range(self.y_size)].count(None) == 0


  def __repr__(self):
    out = ""

    for yi,ys in enumerate(self.grid):
      if yi == 0:
        out += "   "
        for x in range(self.x_size):
          if self.is_col_blocked(x):
            out += "B "
          else:
            out += "  "
        out += "\n"

      if self.is_row_blocked(ys):
        out += "B "
      else:
        out += "  "

      for x in ys:
        if x is None:
          out += "| "
        else:
          out += "|" + x

      if self.is_row_blocked(ys) and ys == ["A","B","C","D","E"]:
        out += " ="

      out += "\n"
    return out

if __name__ == "__main__":
  g = Grid("",5,5)
  g.push_left(0,"x")
  g.push_left(0,"y")
  g.push_top(1,"x")
  g.push_top(2,"y")
  g.push_top(1,"x")
  g.push_left(0,"y")
  g.push_left(3,"x")
  g.push_left(3,"y")
  g.push_left(3,"x")
  g.push_left(3,"y")
  g.push_left(3,"x")
  g.push_bottom(3,"y")
  g.push_bottom(3,"x")
  g.push_bottom(3,"y")
  g.push_left(1,"H")
  g.push_left(1,"H")
  g.push_left(1,"H")
  g.push_top(1,"Z")
  g.push_top(4,"Z")
  print(g)
