#pragma once

#include <boost/serialization/nvp.hpp>
#include <iostream>

namespace SP_QSP_IO{
//! 3D coordinates, floating point 

class Coord3D_f
{
public:
	Coord3D_f();
	Coord3D_f(double, double, double);
	~Coord3D_f();

	Coord3D_f operator+(const Coord3D_f&) const;
	Coord3D_f operator-(const Coord3D_f&) const;
	double dot(const Coord3D_f&) const;

	// length of vector
	double length(void) const;
	// distance to a line 
	double dist_to_line(const Coord3D_f&, const Coord3D_f&);

	friend std::ostream & operator<<(std::ostream &os, const Coord3D_f & g); 
	//! x value
	double x;
	//! y
	double y;
	//! z
	double z;

private:
	friend class boost::serialization::access;
	//! boost serialization
	template<class Archive>
	void serialize(Archive & ar, const unsigned int /*version*/);

};

inline Coord3D_f Coord3D_f::operator+(const Coord3D_f& c) const{
	return Coord3D_f(x + c.x, y + c.y, z + c.z);
}

inline Coord3D_f Coord3D_f::operator-(const Coord3D_f& c) const{
	return Coord3D_f(x - c.x, y - c.y, z - c.z);
}

inline double Coord3D_f::dot(const Coord3D_f& c) const{
	return x*c.x + y * c.y + z * c.z;
}

template<class Archive>
inline void Coord3D_f::serialize(Archive & ar, const unsigned int /* version */){
	ar & BOOST_SERIALIZATION_NVP(x);
	ar & BOOST_SERIALIZATION_NVP(y);
	ar & BOOST_SERIALIZATION_NVP(z);
}

inline std::ostream & operator<<(std::ostream &os, const Coord3D_f& c) {
	os << "(" << c.x << ", " << c.y << ", " << c.z << ")";
	return os;
}

};// end of namespace