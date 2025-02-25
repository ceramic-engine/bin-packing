package binpacking;

enum abstract FreeRectChoiceHeuristic(Int) from Int to Int {
	var BestShortSideFit = 1;
	var BestLongSideFit = 2;
	var BestAreaFit = 3;
	var BottomLeftRule = 4;
	var ContactPointRule = 5;
}

class MaxRectsPackerBestFitPosition {
	public var bestNode:Rect = null;
	public var bestAreaFit:Int = -1;
	public var bestShortSideFit:Int = -1;
	public var bestLongSideFit:Int = -1;
	public var bestContactScore:Int = -1;
	public var bestX:Int = -1;
	public var bestY:Int = -1;
	public function new() {}
}

@:structInit
class MaxRectsPackerRectScore {
	public var rect:Rect;
	public var primaryScore:Int;
	public var secondaryScore:Int;
}

class MaxRectsPacker implements IOccupancy {
	public var binWidth(default, null):Int;
	public var binHeight(default, null):Int;
	public var binAllowFlip(default, null):Bool;
	public var usedRectangles(default, null):Array<Rect> = new Array<Rect>();
	public var freeRectangles(default, null):Array<Rect> = new Array<Rect>();

	var _bestFitPosition = new MaxRectsPackerBestFitPosition();

	public function new(width:Int = 0, height:Int = 0, allowFlip:Bool = true) {
		binWidth = width;
		binHeight = height;
		binAllowFlip = allowFlip;

		var n = new Rect(0, 0, width, height);

		freeRectangles.push(n);
	}

	public function insert(width:Int, height:Int, method:FreeRectChoiceHeuristic):Rect {
		var newNode:Rect = switch(method) {
			case FreeRectChoiceHeuristic.BestShortSideFit:
				findPositionForNewNodeBestShortSideFit(width, height, _bestFitPosition).bestNode;
			case FreeRectChoiceHeuristic.BottomLeftRule:
				findPositionForNewNodeBottomLeft(width, height, _bestFitPosition).bestNode;
			case FreeRectChoiceHeuristic.ContactPointRule:
				findPositionForNewNodeContactPoint(width, height, _bestFitPosition).bestNode;
			case FreeRectChoiceHeuristic.BestLongSideFit:
				findPositionForNewNodeBestLongSideFit(width, height, _bestFitPosition).bestNode;
			case FreeRectChoiceHeuristic.BestAreaFit:
				findPositionForNewNodeBestAreaFit(width, height, _bestFitPosition).bestNode;
		}

		if (newNode == null || newNode.width == 0 || newNode.height == 0) {
			return null;
		}

		var numRectanglesToProcess = freeRectangles.length;

		var i = 0;
		while (i < numRectanglesToProcess) {
			if (splitFreeNode(freeRectangles[i], newNode)) {
				freeRectangles.splice(i, 1);
				--i;
				--numRectanglesToProcess;
			}
			i++;
		}

		pruneFreeList();

		usedRectangles.push(newNode);
		return newNode;
	}

	public function occupancy():Float {
		if (usedRectangles.length == 0) {
			return 0.0;
		}

		var usedSurfaceArea:Float = 0;

		for (i in 0...usedRectangles.length) {
			usedSurfaceArea += usedRectangles[i].width * usedRectangles[i].height;
		}

		return usedSurfaceArea / (binWidth * binHeight);
	}

	private function scoreRect(width:Int, height:Int, method:FreeRectChoiceHeuristic):MaxRectsPackerRectScore {
		var newNode:Rect = new Rect();
		var score1:Int = 0x3FFFFFFF;
		var score2:Int = 0x3FFFFFFF;

		switch(method) {
			case FreeRectChoiceHeuristic.BestShortSideFit:
				var data = findPositionForNewNodeBestShortSideFit(width, height, _bestFitPosition);
				newNode = data.bestNode;
				score1 = data.bestShortSideFit;
				score2 = data.bestLongSideFit;
			case FreeRectChoiceHeuristic.BottomLeftRule:
				var data = findPositionForNewNodeBottomLeft(width, height, _bestFitPosition);
				newNode = data.bestNode;
				score1 = data.bestY;
				score2 = data.bestX;
			case FreeRectChoiceHeuristic.ContactPointRule:
				var data = findPositionForNewNodeContactPoint(width, height, _bestFitPosition);
				newNode = data.bestNode;
				score1 = -data.bestContactScore;
			case FreeRectChoiceHeuristic.BestLongSideFit:
				var data = findPositionForNewNodeBestLongSideFit(width, height, _bestFitPosition);
				newNode = data.bestNode;
				score1 = data.bestLongSideFit;
				score2 = data.bestLongSideFit;
			case FreeRectChoiceHeuristic.BestAreaFit:
				var data = findPositionForNewNodeBestAreaFit(width, height, _bestFitPosition);
				newNode = data.bestNode;
				score1 = data.bestAreaFit;
				score2 = data.bestShortSideFit;
		}

		if (newNode.height == 0) {
			score1 = 0x3FFFFFFF;
			score2 = 0x3FFFFFFF;
		}

		return { rect: newNode, primaryScore: score1, secondaryScore: score2 };
	}

	private function contactPointScoreNode(x:Int, y:Int, width:Int, height:Int):Int {
		var score = 0;

		if (x == 0 || x + width == binWidth) {
			score += height;
		}
		if (y == 0 || y + height == binHeight) {
			score += width;
		}

		for (i in 0...usedRectangles.length) {
			if (usedRectangles[i].x == x + width || usedRectangles[i].x + usedRectangles[i].width == x) {
				score += Std.int(commonIntervalLength(usedRectangles[i].y, usedRectangles[i].height, y, y + height));
			}
			if (usedRectangles[i].y == y + height || usedRectangles[i].y + usedRectangles[i].height == y) {
				score += Std.int(commonIntervalLength(usedRectangles[i].x, usedRectangles[i].x + usedRectangles[i].width, x, x + width));
			}
		}

		return score;
	}

	private function findPositionForNewNodeBottomLeft(width:Int, height:Int, result:MaxRectsPackerBestFitPosition):MaxRectsPackerBestFitPosition {
		var bestNode:Rect = new Rect();

		var bestY = 0x3FFFFFFF;
		var bestX = 0x3FFFFFFF;

		for (i in 0...freeRectangles.length) {
			if (freeRectangles[i].width >= width && freeRectangles[i].height < bestX) {
				var topSideY = Std.int(freeRectangles[i].y + height);

				bestNode.x = freeRectangles[i].x;
				bestNode.y = freeRectangles[i].y;
				bestNode.width = width;
				bestNode.height = height;
				bestY = topSideY;
				bestX = Std.int(freeRectangles[i].x);
			}

			if (binAllowFlip && freeRectangles[i].width >= height && freeRectangles[i].height >= width) {
				var topSideY = Std.int(freeRectangles[i].y + height);

				bestNode.x = freeRectangles[i].x;
				bestNode.y = freeRectangles[i].y;
				bestNode.width = width;
				bestNode.height = height;
				bestY = topSideY;
				bestX = Std.int(freeRectangles[i].x);
			}
		}

		result.bestNode = bestNode;
		result.bestY = bestY;
		result.bestX = bestX;
		return result;
	}

	private function findPositionForNewNodeBestShortSideFit(width:Int, height:Int, result:MaxRectsPackerBestFitPosition):MaxRectsPackerBestFitPosition {
		var bestNode:Rect = new Rect();

		var bestShortSideFit = 0x3FFFFFFF;
		var bestLongSideFit = 0x3FFFFFFF;

		for (i in 0...freeRectangles.length) {
			if (freeRectangles[i].width >= width && freeRectangles[i].height >= height) {
				var leftoverHoriz = Math.abs(freeRectangles[i].width - width);
				var leftoverVert = Math.abs(freeRectangles[i].height - height);
				var shortSideFit = Math.min(leftoverHoriz, leftoverVert);
				var longSideFit = Math.max(leftoverHoriz, leftoverVert);

				if (shortSideFit < bestShortSideFit || (shortSideFit == bestShortSideFit && longSideFit < bestLongSideFit)) {
					bestNode.x = freeRectangles[i].x;
					bestNode.y = freeRectangles[i].y;
					bestNode.width = width;
					bestNode.height = height;
					bestShortSideFit = Std.int(shortSideFit);
					bestLongSideFit = Std.int(longSideFit);
				}
			}

			if (binAllowFlip && freeRectangles[i].width >= height && freeRectangles[i].height >= width) {
				var flippedLeftoverHoriz = Math.abs(freeRectangles[i].width - height);
				var flippedLeftoverVert = Math.abs(freeRectangles[i].height - width);
				var flippedShortSideFit = Math.min(flippedLeftoverHoriz, flippedLeftoverVert);
				var flippedLongSideFit = Math.max(flippedLeftoverHoriz, flippedLeftoverVert);

				if (flippedShortSideFit < bestShortSideFit || (flippedShortSideFit == bestShortSideFit && flippedLongSideFit < bestLongSideFit)) {
					bestNode.x = freeRectangles[i].x;
					bestNode.y = freeRectangles[i].y;
					bestNode.width = height;
					bestNode.height = width;
					bestNode.flipped = !bestNode.flipped;
					bestShortSideFit = Std.int(flippedShortSideFit);
					bestLongSideFit = Std.int(flippedLongSideFit);
				}
			}
		}

		result.bestNode = bestNode;
		result.bestShortSideFit = bestShortSideFit;
		result.bestLongSideFit = bestLongSideFit;
		return result;
	}

	private function findPositionForNewNodeBestLongSideFit(width:Int, height:Int, result:MaxRectsPackerBestFitPosition):MaxRectsPackerBestFitPosition {
		var bestNode:Rect = new Rect();

		var bestShortSideFit = 0x3FFFFFFF;
		var bestLongSideFit = 0x3FFFFFFF;

		for (i in 0...freeRectangles.length) {
			if (freeRectangles[i].width >= width && freeRectangles[i].height >= height) {
				var leftoverHoriz = Math.abs(freeRectangles[i].width - width);
				var leftoverVert = Math.abs(freeRectangles[i].height - height);
				var shortSideFit = Math.min(leftoverHoriz, leftoverVert);
				var longSideFit = Math.max(leftoverHoriz, leftoverVert);

				if (longSideFit < bestLongSideFit || (longSideFit == bestLongSideFit && shortSideFit < bestShortSideFit)) {
					bestNode.x = freeRectangles[i].x;
					bestNode.y = freeRectangles[i].y;
					bestNode.width = width;
					bestNode.height = height;
					bestShortSideFit = Std.int(shortSideFit);
					bestLongSideFit = Std.int(longSideFit);
				}
			}

			if (binAllowFlip && freeRectangles[i].width >= height && freeRectangles[i].height >= width) {
				var leftoverHoriz = Math.abs(freeRectangles[i].width - width);
				var leftoverVert = Math.abs(freeRectangles[i].height - height);
				var shortSideFit = Math.min(leftoverHoriz, leftoverVert);
				var longSideFit = Math.max(leftoverHoriz, leftoverVert);

				if (longSideFit < bestLongSideFit || (longSideFit == bestLongSideFit && shortSideFit < bestShortSideFit)) {
					bestNode.x = freeRectangles[i].x;
					bestNode.y = freeRectangles[i].y;
					bestNode.width = height;
					bestNode.height = width;
					bestNode.flipped = !bestNode.flipped;
					bestShortSideFit = Std.int(shortSideFit);
					bestLongSideFit = Std.int(longSideFit);
				}
			}
		}

		result.bestNode = bestNode;
		result.bestShortSideFit = bestShortSideFit;
		result.bestLongSideFit = bestLongSideFit;
		return result;
	}

	private function findPositionForNewNodeBestAreaFit(width:Int, height:Int, result:MaxRectsPackerBestFitPosition):MaxRectsPackerBestFitPosition {
		var bestNode:Rect = new Rect();

		var bestAreaFit = 0x3FFFFFFF;
		var bestShortSideFit = 0x3FFFFFFF;

		for(i in 0...freeRectangles.length) {
			var areaFit = freeRectangles[i].width * freeRectangles[i].height - width * height;

			if (freeRectangles[i].width >= width && freeRectangles[i].height >= height) {
				var leftoverHoriz = Math.abs(freeRectangles[i].width - width);
				var leftoverVert = Math.abs(freeRectangles[i].height - height);
				var shortSideFit = Math.min(leftoverHoriz, leftoverVert);

				if (areaFit < bestAreaFit || (areaFit == bestAreaFit && shortSideFit < bestShortSideFit)) {
					bestNode.x = freeRectangles[i].x;
					bestNode.y = freeRectangles[i].y;
					bestNode.width = width;
					bestNode.height = height;
					bestShortSideFit = Std.int(shortSideFit);
					bestAreaFit = Std.int(areaFit);
				}
			}

			if (binAllowFlip && freeRectangles[i].width >= height && freeRectangles[i].height >= width) {
				var leftoverHoriz = Math.abs(freeRectangles[i].width - height);
				var leftoverVert = Math.abs(freeRectangles[i].height - width);
				var shortSideFit = Math.min(leftoverHoriz, leftoverVert);

				if (areaFit < bestAreaFit || (areaFit == bestAreaFit && shortSideFit < bestShortSideFit)) {
					bestNode.x = freeRectangles[i].x;
					bestNode.y = freeRectangles[i].y;
					bestNode.width = height;
					bestNode.height = width;
					bestNode.flipped = !bestNode.flipped;
					bestShortSideFit = Std.int(shortSideFit);
					bestAreaFit = Std.int(areaFit);
				}
			}
		}

		result.bestNode = bestNode;
		result.bestAreaFit = bestAreaFit;
		result.bestShortSideFit = bestShortSideFit;
		return result;
	}

	private function findPositionForNewNodeContactPoint(width:Int, height:Int, result:MaxRectsPackerBestFitPosition):MaxRectsPackerBestFitPosition {
		var bestNode:Rect = new Rect();

		var bestContactScore = -1;

		for (i in 0...freeRectangles.length) {
			if (freeRectangles[i].width >= width && freeRectangles[i].height >= height) {
				var score = contactPointScoreNode(Std.int(freeRectangles[i].x), Std.int(freeRectangles[i].y), width, height);
				if (score > bestContactScore) {
					bestNode.x = freeRectangles[i].x;
					bestNode.y = freeRectangles[i].y;
					bestNode.width = width;
					bestNode.height = height;
					bestContactScore = score;
				}
			}

			if (freeRectangles[i].width >= height && freeRectangles[i].height >= width) {
				var score = contactPointScoreNode(Std.int(freeRectangles[i].x), Std.int(freeRectangles[i].y), height, width);
				if (score > bestContactScore) {
					bestNode.x = freeRectangles[i].x;
					bestNode.y = freeRectangles[i].y;
					bestNode.width = height;
					bestNode.height = width;
					bestNode.flipped = !bestNode.flipped;
					bestContactScore = score;
				}
			}
		}

		result.bestNode = bestNode;
		result.bestContactScore = bestContactScore;
		return result;
	}

	private function splitFreeNode(freeNode:Rect, usedNode:Rect):Bool {
	if (usedNode.x >= freeNode.x + freeNode.width ||
		usedNode.x + usedNode.width <= freeNode.x ||
		usedNode.y >= freeNode.y + freeNode.height ||
		usedNode.y + usedNode.height <= freeNode.y) {
			return false;
		}

		if (usedNode.x < freeNode.x + freeNode.width && usedNode.x + usedNode.width > freeNode.x) {
			if (usedNode.y > freeNode.y && usedNode.y < freeNode.y + freeNode.height) {
				var newNode = freeNode.clone();
				newNode.height = usedNode.y - newNode.y;
				freeRectangles.push(newNode);
			}
			if (usedNode.y + usedNode.height < freeNode.y + freeNode.height) {
				var newNode = freeNode.clone();
				newNode.y = usedNode.y + usedNode.height;
				newNode.height = freeNode.y + freeNode.height - (usedNode.y + usedNode.height);
				freeRectangles.push(newNode);
			}
		}

		if (usedNode.y < freeNode.y + freeNode.height && usedNode.y + usedNode.height > freeNode.y) {
			if (usedNode.x > freeNode.x && usedNode.x < freeNode.x + freeNode.width) {
				var newNode = freeNode.clone();
				newNode.width = usedNode.x - newNode.x;
				freeRectangles.push(newNode);
			}
			if (usedNode.x + usedNode.width < freeNode.x + freeNode.width) {
				var newNode = freeNode.clone();
				newNode.x = usedNode.x + usedNode.width;
				newNode.width = freeNode.x + freeNode.width - (usedNode.x + usedNode.width);
				freeRectangles.push(newNode);
			}
		}

		return true;
	}

	private function pruneFreeList():Void {
		var i = 0;
		while (i < freeRectangles.length) {
			var j = i + 1;
			while (j < freeRectangles.length) {
				if (freeRectangles[i].isContainedIn(freeRectangles[j])) {
					freeRectangles.splice(i, 1);
					i--;
					break;
				}

				if (freeRectangles[j].isContainedIn(freeRectangles[i])) {
					freeRectangles.splice(j, 1);
					continue;
				}

				j++;
			}
			i++;
		}
	}

	private function commonIntervalLength(i1start:Float, i1end:Float, i2start:Float, i2end:Float):Float {
		if (i1end < i2start || i2end < i1start) {
			return 0;
		}
		return (i1end < i2end ? i1end : i2end) - (i1start > i2start ? i1start : i2start);
	}
}