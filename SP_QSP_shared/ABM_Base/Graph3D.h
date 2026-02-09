#pragma once

#include <boost/graph/adjacency_list.hpp>
#include <boost/graph/adj_list_serialize.hpp>
#include <boost/serialization/nvp.hpp>
#include <iostream>

#include <vector>
#include <string>

#include "Coord3D_f.h"
#include "Grid3D.h"

namespace SP_QSP_IO{

class Graph3D
{
public:
	Graph3D();
	virtual ~Graph3D();

	struct vertex_c{
		typedef boost::vertex_property_tag kind;
	};
	struct edge_thickness{
		typedef boost::edge_property_tag kind;
	};
	typedef boost::property<vertex_c, Coord3D_f> VertexCoordProperty;
	typedef boost::property<edge_thickness, double> EdgeThicknessProperty;
	//! graph object type: undirected
	typedef boost::adjacency_list< boost::listS, boost::vecS, boost::undirectedS, 
		VertexCoordProperty, EdgeThicknessProperty> udgraph;

	//! add vertex and set coordinates
	void add_vertex(const double, const double, const double);
	void add_vertex(const Coord3D_f&);

	//! add edge
	bool add_edge(const unsigned int, const unsigned int, const double);

	//! get graph (const)
	const udgraph& get_graph()const{ return _graph; };
	//! get graph
	udgraph& get_graph(){ return _graph; };

	//! get vertex coordinates
	Coord3D_f get_coord(unsigned int) const;
	//! set vertex coordinates
	bool set_coord(unsigned int, Coord3D_f&);
	//! get edge thickness
	double get_thickness(unsigned int, unsigned int) const;
	//! set edge thickness
	bool set_thickness(unsigned int, unsigned int, double);

	//! rasterize one edge
	bool rasterize_edge(unsigned int, unsigned int, Grid3D<int>&, double);
	//! rasterize entire graph 
	bool rasterize_graph(Grid3D<int>&, double);

	//! graph from file
	bool read_graph(const std::string & inFileName);

	friend std::ostream & operator<<(std::ostream &os, const Graph3D& g);

private:

	//! check if vertex already exist
	bool valid_vertex(const unsigned int) const;

	//! Graph object
	udgraph _graph;

	friend class boost::serialization::access;
	//! boost serialization
	template<class Archive>
	void serialize(Archive & ar, const unsigned int /*version*/);

};

template<class Archive>
inline void Graph3D::serialize(Archive & ar, const unsigned int /* version */){
	ar & BOOST_SERIALIZATION_NVP(_graph);
}

inline std::ostream & operator<<(std::ostream &os, const Graph3D& g) {
	const Graph3D::udgraph& _g = g.get_graph();
	// number of vertices/edges
	os << boost::num_vertices(_g) << ", " << boost::num_edges(_g) << std::endl;

	// vertex
	for (auto v : boost::make_iterator_range(boost::vertices(_g))){
		os << v << ", " << g.get_coord(v) << std::endl;
	}
	// edges
	auto thickness_edge = boost::get(Graph3D::edge_thickness(), _g);
	for (auto e : boost::make_iterator_range(boost::edges(_g))){
		os << boost::source(e, _g) << ", " << boost::target(e, _g) << ", "
			<< boost::get(thickness_edge, e)
			<< std::endl;
	}
	return os;
}

};// end of namespace

