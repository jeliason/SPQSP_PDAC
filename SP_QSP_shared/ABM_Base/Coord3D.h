#ifndef __COORD3D_H__
#define __COORD3D_H__

#include <boost/serialization/nvp.hpp>
#include <math.h>
#include <iostream>
#include <stdexcept>

namespace SP_QSP_IO{
//! 3D coordinate 
class Coord3D
{
public:
	Coord3D();
	Coord3D(int x, int y, int z);
	~Coord3D();

	bool operator==(const Coord3D&) const;
	bool operator!=(const Coord3D&) const;
	Coord3D operator+(const Coord3D&) const;
	Coord3D operator-(const Coord3D&) const;
	Coord3D operator/(int) const;
	Coord3D operator%(const Coord3D&) const;
	Coord3D operator-() const;
	Coord3D& operator=(const Coord3D&);
	bool operator<(const Coord3D&) const;
	bool inRange(const Coord3D&) const;
	int size() const;
	double length() const;
	int operator[](int dimension) const;
	int& operator[](int dimension);

	friend std::ostream & operator<<(std::ostream &os, const Coord3D & g); 

	//! x value
	int x;
	//! y
	int y;
	//! z
	int z;
private:
	friend class boost::serialization::access;
	//! boost serialization
	template<class Archive>
	void serialize(Archive & ar, const unsigned int /*version*/);
};

inline bool Coord3D::operator==(const Coord3D& c) const{
	return (x == c.x && y == c.y && z == c.z);
}

inline bool Coord3D::operator!=(const Coord3D& c) const{
	return (x != c.x || y != c.y || z != c.z);
}

inline Coord3D Coord3D::operator+(const Coord3D& c) const{
	return Coord3D(x + c.x, y + c.y, z + c.z);
}

inline Coord3D Coord3D::operator-(const Coord3D& c) const{
	return Coord3D(x - c.x, y - c.y, z - c.z);
}

inline Coord3D& Coord3D::operator=(const Coord3D& c){
	x = c.x;
	y = c.y;
	z = c.z;
	return *this;
}

inline Coord3D Coord3D::operator/(int s) const{
	return Coord3D(x/s , y/s, z/s);
}

inline Coord3D Coord3D::operator%(const Coord3D& c) const{
	return Coord3D(((x % c.x)+c.x)%c.x, 
				   ((y % c.y)+c.y)%c.y, 
				   ((z % c.z)+c.z)%c.z);
}

inline Coord3D Coord3D::operator-() const{
	return Coord3D(-x, -y, -z);
}

inline bool Coord3D::operator<(const Coord3D& c) const{
	return x < c.x || (x == c.x && (y < c.y || (y == c.y && z < c.z)));
}
inline bool Coord3D::inRange(const Coord3D& c) const{
	return x >= 0 && x < c.x
		&& y >= 0 && y < c.y
		&& z >= 0 && z < c.z;
}
inline int Coord3D::size() const{
	return x * y * z;
}

inline double Coord3D::length()const{
	double sum_sqr = (double)x*x + (double)y*y + (double)z*z;
	/*
	std::cout << x << "," << y << "," << z << "; " 
		<< sum_sqr << std::endl;
	*/
	return pow(sum_sqr, 0.5);
}

inline int Coord3D::operator[](int dimension) const {
	if (dimension == 0) {
		return x;
	}
	else if (dimension == 1) {
		return y;
	}
	else if (dimension == 2) {
		return z;
	}
	else {
		throw std::invalid_argument("invalid dimension");
	}
}
inline int& Coord3D::operator[](int dimension) {
	if (dimension == 0) {
		return x;
	}
	else if (dimension == 1) {
		return y;
	}
	else if (dimension == 2) {
		return z;
	}
	else {
		throw std::invalid_argument("invalid dimension");
	}
}

template<class Archive>
inline void Coord3D::serialize(Archive & ar, const unsigned int /* version */){
	ar & BOOST_SERIALIZATION_NVP(x);
	ar & BOOST_SERIALIZATION_NVP(y);
	ar & BOOST_SERIALIZATION_NVP(z);
}

inline std::ostream & operator<<(std::ostream &os, const Coord3D& c) {
		os << "(" << c.x << ", " << c.y << ", "<< c.z << ")";
		return os;
};

};
#endif
