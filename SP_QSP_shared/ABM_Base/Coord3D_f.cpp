#include "Coord3D_f.h"

#include <math.h>
namespace SP_QSP_IO{

Coord3D_f::Coord3D_f()
	: x(0)
	, y(0)
	, z(0)
{
}
Coord3D_f::Coord3D_f(double a, double b, double c)
	: x(a)
	, y(b)
	, z(c)
{
}

Coord3D_f::~Coord3D_f()
{
}

double Coord3D_f::length(void) const{
	return pow(x*x + y*y + z*z, 0.5);
}


double Coord3D_f::dist_to_line(const Coord3D_f& source, const Coord3D_f& target){
	auto l = target - source;
	auto m = *this - source;
	auto n = *this - target;
	double cos_theta = m.dot(n) / m.length() / n.length();
	double sin_theta = pow(1 - cos_theta*cos_theta, 0.5);
	double numerator = m.length()*n.length()*sin_theta;
	double denominator = l.length();
	return numerator / denominator;
}

};
