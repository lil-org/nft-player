tokenData = tokenData.hashes[0].substring(2);
int[] hp = new int[32];

void setup() {
	size(window.innerWidth>window.innerHeight*4/3?window.innerHeight*4/3:window.innerWidth, window.innerWidth>window.innerHeight*4/3?window.innerHeight:window.innerWidth*3/4);
	for (int i = 0; i < 32; i = i + 1) {
		hp[i] = unhex(tokenData.substring(i + i, i + i + 2));
	}
	background(hp[0], hp[1], hp[2], A(hp[3]));
}

int B(int _num){
	return (int) map(_num, 0, 255, 100, 255);
}

int C(int _num) {
	return (int) map(_num, 0, 255, 0, 255);
}

int A(int _num) {
	return (int) map(_num, 0, 255, 50, 100);
}

int G(_num) {
	return (int) map(_num, 0, 255, 100, 200);
}

int X(int _num) {
	float padding = width * 0.2;
	return (int) map(_num, 0, 255, padding, width - padding);
}
int Y(int _num) {
	float padding = height * 0.2;
	return (int) map(_num, 0, 255, padding, height - padding);
}
int R(int _num) {
	return (int) map(_num, 0, 255, 0, 32);
}

void draw() {
	noLoop();
	background(B(hp[28]),B(hp[29]),B(hp[30]));
	Grid grid = new Grid(R(hp[0]), R(hp[1]));
	if (hp[2] > 150) {
		grid.show_diagonal(hp[3]);
		grid.show_diagonal(-hp[4]);
	} else if (hp[2] > 85) {
		grid.show_horizontal();
		grid.show_vertical();
	}

	Rectangle rectangle1 = new Rectangle(X(hp[5]), Y(hp[6]), R(hp[7]));
	if (hp[8] > 0 && hp[8] < 85) {
		rectangle1.show5(C(hp[9]), C(hp[10]), C(hp[11]), A(hp[12]));
	} else if (hp[8] > 84 && hp[8] < 170) {
		rectangle1.show3(C(hp[9]), C(hp[10]), C(hp[11]), A(hp[12]));
	} else {
		rectangle1.show1(C(hp[9]), C(hp[10]), C(hp[11]), A(hp[12]));
	}

	LineMaker lines = new LineMaker(hp);
	if (R(hp[14]) == 10) {
		lines.show_points(4);
		lines.compute_distance(100);
	} else if (R(hp[14]) == 11) {
		lines.show_points(4);
	} else if (R(hp[14]) == 12) {
		lines.show_scribble();
	} else if (R(hp[14]) == 13) {
		lines.show_lines(R(hp[13]));
	} else if (R(hp[14]) == 14) {
		lines.show_complex_lines(R(hp[15]));
	} else if (R(hp[14]) == 15) {
		lines.show_stars(R(hp[15]));
	} else if (R(hp[14]) == 16) {
		lines.show_points(15);
		lines.show_points(10);
		lines.show_points(5);
	} else if (R(hp[14]) == 17) {
		lines.show_points(R(hp[16]));
	} else if (R(hp[14]) == 18) {
		lines.show_dots();
	} else if (R(hp[14]) == 19) {
		lines.draw_bezier_disjoint();
	} else if (R(hp[14]) == 20) {
		lines.show_points(5);
		lines.show_lines(R(hp[13]));
		lines.show_dots();
		lines.show_stars(R(hp[0]));
		lines.show_complex_lines(R(hp[15]));
	} else if (R(hp[14]) == 21) {
		lines.compute_distance(100);
	} else if (R(hp[14]) > 21 && R(hp[14]) < 28) {
		lines.show_stars(R(hp[1]));
	}

	Rectangle rectangle2 = new Rectangle(X(hp[18]), Y(hp[19]), R(hp[21]));
	if (hp[20] > 0 && hp[20] < 85) {
		rectangle2.show5(C(hp[22]), C(hp[23]), C(hp[24]), A(hp[25]));
	} else if (hp[20] > 84 && hp[20] < 170) {
		rectangle2.show3(C(hp[22]), C(hp[23]), C(hp[24]), A(hp[25]));
	} else {
		rectangle2.show1(C(hp[22]), C(hp[23]), C(hp[24]), A(hp[25]));
	}

	Trapezoid trap1 = new Trapezoid(X(hp[27]), Y(hp[28]), X(hp[29]), Y(hp[30]), X(hp[31]), Y(hp[0]), X(hp[1]), Y(hp[2]));
	if (hp[26] > 210) {
		trap1.show_lines(0, 0, 0, 255);
	} else if (hp[26] > 168) {
		trap1.show_lines(C(hp[3]), C(hp[4]), C(hp[5]), A(hp[6]));
	} else if (hp[26] > 126) {
		trap1.show_shapes(C(hp[3]), C(hp[4]), C(hp[5]), A(hp[6]));
	} else if (hp[26] > 84) {
		trap1.show_lines(C(hp[3]), C(hp[4]), C(hp[5]), 255);
	} else if (hp[26] > 42) {
		lines.draw_bezier();
	} else {
		trap1.show_lines(255, 255, 255, 255);
	}
	Trapezoid trap2 = new Trapezoid(X(hp[7]), Y(hp[8]), X(hp[9]), Y(hp[10]), X(hp[11]), Y(hp[12]), X(hp[13]), Y(hp[14]));
	trap2.show_shapes(C(hp[15]), C(hp[16]), C(hp[17]), A(hp[18]));
}
class LineMaker {
	PVector[] points_array;
	LineMaker(int[] _hp) {
		points_array = new PVector[_hp.length()];
		for (int i = 0; i < _hp.length(); i++) {
			if (i == _hp.length - 1) {
				points_array[i] = new PVector(X(_hp[i]), Y(_hp[0]));
			} else {
				points_array[i] = new PVector(X(_hp[i]), Y(_hp[i + 1]));
			}
		}
	}

	void show_points(int size) {
		color fill1 = color(255, 255, 255, 50);
		fill(fill1);
		noStroke();
		for (int i = 0; i < points_array.length; i++) {
			ellipse(points_array[i].x, points_array[i].y, size, size);
		}
	}

	void compute_distance(int max_distance) {
		for (int i = 0; i < points_array.length; i++) {
			for (int j = 0; j < points_array.length; j++) {
				if (dist(points_array[i].x, points_array[i].y, points_array[j].x, points_array[j].y) < max_distance) {
					if (dist(points_array[i].x, points_array[i].y, points_array[j].x, points_array[j].y) != 0) {
						if ((points_array[i].x != points_array[j].x) && (points_array[i].y != points_array[j].y)) {
							strokeWeight(1);
							stroke(0, 0, 0, 255);
							line(points_array[i].x, points_array[i].y, points_array[j].x, points_array[j].y);
						}
					}
				}
			}
		}
	}

	void show_scribble() {
		noFill();
		strokeWeight(1);
		stroke(255, 255, 255, 75);
		for (int i = 0; i < points_array.length; i++) {
			if (i < points_array.length - 1) {
				line(points_array[i].x, points_array[i].y, points_array[i + 1].x, points_array[i + 1].y);
			} else {
				line(points_array[i].x, points_array[i].y, points_array[0].x, points_array[0].y);
			}
		}
	}

	void show_lines(int divider) {
		noFill();
		strokeWeight(1);
		stroke(255, 255, 255, 75);
		for (int i = 0; i < points_array.length; i++) {
			if (i % divider == 0) {
				if (i < points_array.length - 1) {
					line(points_array[i].x, points_array[i].y, points_array[i + 1].x, points_array[i + 1].y);
				} else {
					line(points_array[i].x, points_array[i].y, points_array[0].x, points_array[0].y);
				}
			}
		}
	}

	void show_complex_lines(int divider) {
		noFill();
		strokeWeight(1);
		stroke(0, 0, 0, 150);
		for (int i = 0; i < points_array.length; i++) {
			if (i % divider == 0) {
				if (i < points_array.length - 3) {
					line(points_array[i].x, points_array[i].y, points_array[i + 1].x, points_array[i + 1].y);
					line(points_array[i + 1].x, points_array[i + 1].y, points_array[i + 2].x, points_array[i + 2].y);
					line(points_array[i + 2].x, points_array[i + 2].y, points_array[i + 3].x, points_array[i + 3].y);
				} else {
					line(points_array[i].x, points_array[i].y, points_array[0].x, points_array[0].y);
					line(points_array[0].x, points_array[0].y, points_array[1].x, points_array[1].y);
					line(points_array[1].x, points_array[1].y, points_array[2].x, points_array[2].y);
				}
			}
		}
	}

	void draw_bezier() {
		noFill();
		strokeWeight(width * 0.0015);
		stroke(255, 255, 255, 255);
		bezier(points_array[12].x, points_array[12].y, points_array[1].x, points_array[1].y, points_array[2].x, points_array[2].y, points_array[3].x, points_array[3].y);
		bezier(points_array[3].x, points_array[3].y, points_array[16].x, points_array[16].y, points_array[17].x, points_array[17].y, points_array[18].x, points_array[18].y);
		bezier(points_array[18].x, points_array[18].y, points_array[26].x, points_array[26].y, points_array[27].x, points_array[27].y, points_array[12].x, points_array[12].y);
	}

	void draw_bezier_disjoint() {
		noFill();
		strokeWeight(width * 0.0015);
		stroke(255, 255, 255, 255);
		bezier(points_array[12].x, points_array[12].y, points_array[1].x, points_array[1].y, points_array[2].x, points_array[2].y, points_array[3].x, points_array[3].y);
		bezier(points_array[5].x, points_array[5].y, points_array[16].x, points_array[16].y, points_array[17].x, points_array[17].y, points_array[18].x, points_array[18].y);
		bezier(points_array[20].x, points_array[20].y, points_array[26].x, points_array[26].y, points_array[27].x, points_array[27].y, points_array[12].x, points_array[12].y);
		strokeWeight(width * 0.0090);
		stroke(255, 255, 255, 90);
		bezier(points_array[12].x, points_array[12].y, points_array[1].x, points_array[1].y, points_array[2].x, points_array[2].y, points_array[3].x, points_array[3].y);
		bezier(points_array[3].x, points_array[3].y, points_array[16].x, points_array[16].y, points_array[17].x, points_array[17].y, points_array[18].x, points_array[18].y);
		bezier(points_array[18].x, points_array[18].y, points_array[26].x, points_array[26].y, points_array[27].x, points_array[27].y, points_array[12].x, points_array[12].y);
		strokeWeight(width * 0.0145);
		stroke(255, 255, 255, 30);
		bezier(points_array[12].x, points_array[12].y, points_array[1].x, points_array[1].y, points_array[2].x, points_array[2].y, points_array[3].x, points_array[3].y);
		bezier(points_array[4].x, points_array[4].y, points_array[16].x, points_array[16].y, points_array[17].x, points_array[17].y, points_array[18].x, points_array[18].y);
		bezier(points_array[19].x, points_array[19].y, points_array[26].x, points_array[26].y, points_array[27].x, points_array[27].y, points_array[12].x, points_array[12].y);
	}

	void show_dots() {
		noStroke();
		pushMatrix();
		for (int i = 0; i < 32; i++) {
			fill(199 * i % 255, 35 * i % 255, 240 * i % 255, 100);
			ellipse(points_array[i].x, points_array[i].y, 20, 20);
			translate(width / 2, height / 2);
			rotate(PI / 4);
			translate(-width / 2, -height / 2);
		}
		popMatrix();
	}

	void show_stars(int line_count) {
		strokeWeight(width * 0.0015);
		noStroke();
		pushMatrix();
		for (int i = 0; i < line_count; i++) {
			if (i == line_count - 1) {
				stroke((199 * i + 10) % 255, (35 * i + 10) % 255, (240 * i + 10) % 255, 100);
				line(points_array[i].x, points_array[i].y, points_array[0].x/3, points_array[0].y/3);
				translate(width / 2, height / 2);
				rotate(PI / 7);
				translate(-width / 2, -height / 2);
			} else {
				stroke((199 * i + 10) % 255, (35 * i + 10) % 255, (240 * i + 10) % 255, 100);
				line(points_array[i].x, points_array[i].y, points_array[i+1].x/3, points_array[i+1].y/3);
				translate(width / 2, height / 2);
				rotate(PI / 7);
				translate(-width / 2, -height / 2);
			}}
			popMatrix();
		}
	}
	
	class Trapezoid {
		PVector p1;
		PVector p2;
		PVector p3;
		PVector p4;

		Trapezoid(int px1, int py1, int px2, int py2, int px3, int py3, int px4, int py4) {
			p1 = new PVector(px1, py1);
			p2 = new PVector(px2, py2);
			p3 = new PVector(px3, py3);
			p4 = new PVector(px4, py4);
		}
		void show_dots(int c1, int c2, int c3, int a) {
			color fill1 = color(c1, c2, c3, a);
			fill(fill1);
			noStroke();
			ellipse(p1.x, p1.y, 10, 10);
			ellipse(p2.x, p2.y, 10, 10);
			ellipse(p3.x, p3.y, 10, 10);
			ellipse(p4.x, p4.y, 10, 10);
		}
		void show_lines(int c1, int c2, int c3, int a) {
			color fill1 = color(c1, c2, c3, a);
			noFill();
			strokeWeight(width * 0.0015);
			stroke(fill1);
			line(p1.x, p1.y, p2.x, p2.y);
			line(p2.x, p2.y, p3.x, p3.y);
			line(p3.x, p3.y, p4.x, p4.y);
			line(p4.x, p4.y, p1.x, p1.y);
			line(p1.x, p1.y, p3.x, p3.y);
			line(p4.x, p4.y, p2.x, p2.y);
		}
		void show_shapes(int c1, int c2, int c3, int a) {
			color fill1 = color(c1, c2, c3, a);
			color fill2 = color(c1, c2, c1, c2);
			fill(fill1);
			noStroke();
			triangle(p1.x, p1.y, p2.x, p2.y, p3.x, p3.y);
			fill(fill2);
			noStroke();
			triangle(p4.x, p4.y, p2.x, p2.y, p3.x, p3.y);
		}
	}
	class Rectangle {
		int rect_height;
		int rect_width;
		int corner_round;
		Rectangle(int _rect_width, int _rect_height, int _corner_round) {
			rect_height = _rect_height;
			rect_width = _rect_width;
			corner_round = _corner_round;
		}
		void show1(int c1, int c2, int c3, int a) {
			color fill1 = color(c1, c2, c3, a);
			fill(fill1);
			noStroke();
			rectMode(CENTER);
			rect(width / 2, height / 2, rect_width, rect_height, corner_round);
		}
		void show3(int c1, int c2, int c3, int a) {
			color fill1 = color(c1, c2, c3, a);
			fill(fill1);
			noStroke();
			rectMode(CENTER);
			if (rect_height > rect_width) {
				rect((width / 2) + (width * 0.2), height / 2, rect_width, rect_height, corner_round);
				rect(width / 2, height / 2, rect_width, rect_height, corner_round);
				rect((width / 2) - (width * 0.2), height / 2, rect_width, rect_height, corner_round);
			} else {
				rect(width / 2, (height / 2) + (height * 0.2), rect_width, rect_height, corner_round);
				rect(width / 2, height / 2, rect_width, rect_height, corner_round);
				rect(width / 2, (height / 2) - (height * 0.2), rect_width, rect_height, corner_round);
			}
		}
		void show5(int c1, int c2, int c3, int a) {
			color fill1 = color(c1, c2, c3, a);
			fill(fill1);
			noStroke();
			rectMode(CENTER);
			if (rect_height > rect_width) {
				rect((width / 2) + (width * 0.2), height / 2, rect_width, rect_height, corner_round);
				rect((width / 2) + (width * 0.1), height / 2, rect_width, rect_height, corner_round);
				rect(width / 2, height / 2, rect_width, rect_height, corner_round);
				rect((width / 2) - (width * 0.1), height / 2, rect_width, rect_height, corner_round);
				rect((width / 2) - (width * 0.2), height / 2, rect_width, rect_height, corner_round);
			} else {
				rect(width / 2, (height / 2) + (height * 0.2), rect_width, rect_height, corner_round);
				rect(width / 2, (height / 2) + (height * 0.1), rect_width, rect_height, corner_round);
				rect(width / 2, height / 2, rect_width, rect_height, corner_round);
				rect(width / 2, (height / 2) - (height * 0.1), rect_width, rect_height, corner_round);
				rect(width / 2, (height / 2) - (height * 0.2), rect_width, rect_height, corner_round);
			}
		}
	}

	class Grid {
		int vertical_divider;
		int horizontal_divider;
		color grid_color = color(100, 100, 100, 300);

		Grid(int p, int q) {
			if (p < 4) {
				p = 4;
			}
			if (q < 4) {
				q = 4;
			}
			vertical_divider = p * 2;
			horizontal_divider = q * 2;
		}

		void show_diagonal(int mixer1) {
			noFill();
			strokeWeight(1);
			stroke(grid_color);
			mixer = mixer1 * 2;
			for (int i = 0 - (vertical_divider * 2); i < width + (vertical_divider * 2); i++) {
				if ((i % vertical_divider) == 0) {
					line(i - mixer1, 0, i + mixer1, height);
				}
			}
		}

		void show_vertical() {
			noFill();
			strokeWeight(1);
			stroke(grid_color);
			PVector start = new PVector(0, 0);
			PVector end = new PVector(width, 0);
			PVector result = new PVector(0, 0);
			for (int i = 0; i < vertical_divider; i++) {
				result = new PVector(start.x + (i / vertical_divider) * (end.x - start.x), start.y + (i / vertical_divider) * (end.y - start.y))
				line(result.x, 0, result.x, height);
			}
			line(width - 1, 0, width - 1, height);
		}

		void show_horizontal() {
			noFill();
			strokeWeight(1);
			stroke(grid_color);
			PVector start = new PVector(0, 0);
			PVector end = new PVector(0, height);
			PVector result = new PVector(0, 0);
			for (int i = 0; i < horizontal_divider; i++) {
				result = new PVector(start.x + (i / horizontal_divider) * (end.x - start.x), start.y + (i / horizontal_divider) * (end.y - start.y))
				line(0, result.y, width, result.y);
			}
			line(0, height - 1, width, height - 1);
		}
	}