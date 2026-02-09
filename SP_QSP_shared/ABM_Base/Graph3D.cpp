#include "Graph3D.h"

#include <boost/property_tree/ptree.hpp>
#include <boost/property_tree/xml_parser.hpp>
#include <boost/foreach.hpp>

namespace SP_QSP_IO{

Graph3D::Graph3D()
{
}


Graph3D::~Graph3D()
{
}


/*! add vertex and set coordinates
	x, y, z: coordinates
*/
void Graph3D::add_vertex(const double x, const double y, const double z){
	boost::add_vertex(Coord3D_f(x, y, z), _graph);
};

void Graph3D::add_vertex(const Coord3D_f& c){
	boost::add_vertex(c, _graph);
}
/*! add edge
	u: source vertex_descriptor  
	v: target vertex_descriptor  
	d: diameter
	only add new edge if
	a. both vertices exist
	b. edge connecting u/v not exist
*/
bool Graph3D::add_edge(const unsigned int u, const unsigned int v, const double d){
	if (valid_vertex(u) && valid_vertex(v))
	{
		// not already exit
		if (!boost::edge(u, v, _graph).second)
		{
			boost::add_edge(u, v, d, _graph);
			return true;
		}
	}
	return false;
};


/*! get coordinates of a vertex
*/
Coord3D_f Graph3D::get_coord(unsigned int v) const{
	return boost::get(boost::get(vertex_c(), _graph), v);
}

/*! set coordinates of a vertex
*/
bool Graph3D::set_coord(unsigned int v, Coord3D_f& c){
	if (valid_vertex(v))
	{
		boost::put(boost::get(vertex_c(), _graph), v, c);
		return true;
	}
	return false;
}

/*! get edge thickness 
*/
double Graph3D::get_thickness(unsigned int u, unsigned int v) const{
	return boost::get(boost::get(edge_thickness(), _graph), 
		boost::edge(u,v,_graph).first);
}

/*! set edge thickness 
*/
bool Graph3D::set_thickness(unsigned int u, unsigned int v, double d){
	if (valid_vertex(u) && valid_vertex(v) && boost::edge(u, v, _graph).second)
	{
		boost::put(boost::get(edge_thickness(), _graph), 
			boost::edge(u, v, _graph).first, d);
		return true;
	}
	return false;
}

//! rasterize one edge
bool Graph3D::rasterize_edge(unsigned int iu, unsigned int iv, Grid3D<int>& grid, double vox){
	using std::max;
	using std::min;
	if (valid_vertex(iu) && valid_vertex(iv) && boost::edge(iu, iv, _graph).second)
	{
		auto u = get_coord(iu);
		auto v = get_coord(iv);
		double diam = get_thickness(iu, iv);
		// should not be thinner than half a voxel
		double r = max(diam, vox)/2;
		auto center_shift = Coord3D_f(vox / 2, vox / 2, vox / 2);
		auto grid_size = grid.getSize3D();

		if (u.x > v.x){
			auto w = v;
			v = u;
			u = w;
		}

		double x0, x1, y0, y1, z0, z1;
		int dy, dz;
		int xstart, xend, ystart, yend, zstart, zend;

		//source
		x0 = u.x;
		y0 = u.y;
		z0 = u.z;
		//target
		x1 = v.x;
		y1 = v.y;
		z1 = v.z;

		// stepsiz
		if (x1 != x0)
		{
			double ky = (y1 - y0) / (x1 - x0);
			double kz = (z1 - z0) / (x1 - x0);
			dy = int((ky*ky + 1)*r / vox);
			dz = int((kz*kz + 1)*r / vox);
		}
		else{
			dy = int((y1 - y0) / 2 / vox);
			dz = int((z1 - z0) / 2 / vox);
		}

		// voxel location
		Coord3D p_vox;
		// center of voxel in real unit
		Coord3D_f p_center;
		// x, y, z are voxels
		int d_pad = int(r / vox) + 1;
		xstart = int(x0 / vox) - d_pad;
		xend = int(x1 / vox) + d_pad;

		int y0_vox = int(y0 / vox);
		int y1_vox = int(y1 / vox);
		int z0_vox = int(z0 / vox);
		int z1_vox = int(z1 / vox);	double dist;
		auto vseg = v - u;

		for (int x = xstart; x <= xend; x++)
		{
			double p_line = x1 == x0 ? 0.5 : ((x + 0.5)*vox - x0) / (x1 - x0);
			int y_line_vox = int((p_line *(y1 - y0) + y0) / vox);
			int z_line_vox = int((p_line *(z1 - z0) + z0) / vox);

			ystart = y_line_vox - dy - 1;
			yend = y_line_vox + dy + 1;
			zstart = z_line_vox - dz - 1;
			zend = z_line_vox + dz + 1;
			bool in_ubox = x < xstart + 2 * d_pad;
			bool in_vbox = x > xend - 2 * d_pad;
			if (in_ubox)
			{
				ystart = min(y0_vox - d_pad, ystart);
				yend = max(y0_vox + d_pad, yend);
				zstart = min(z0_vox - d_pad, zstart);
				zend = max(z0_vox + d_pad, zend);
			}
			if (in_vbox)
			{
				ystart = min(y1_vox - d_pad, ystart);
				yend = max(y1_vox + d_pad, yend);
				zstart = min(z1_vox - d_pad, zstart);
				zend = max(z1_vox + d_pad, zend);
			}

			for (int y = ystart; y <= yend; y++)
			{
				for (int z = zstart; z <= zend; z++){
					p_vox = Coord3D(x, y, z);
					p_center = Coord3D_f(x*vox, y*vox, z*vox) + center_shift;

					if (vseg.dot(p_center - u) < 0)
					{
						dist = (p_center - u).length();
					}
					else if (vseg.dot(p_center - v) > 0){
						dist = (p_center - v).length();
					}
					else{
						dist = p_center.dist_to_line(u, v);
					}
					if (dist <= r){
						if (p_vox.inRange(grid_size)){
							grid(x, y, z) = 1;
						}
					}
				}
			}
		}
	}
	return false;

}

/*! rasterize entire graph
*/
bool Graph3D::rasterize_graph(Grid3D<int>& grid, double vox){
	for (auto e : boost::make_iterator_range(boost::edges(_graph))){
		rasterize_edge(boost::source(e, _graph), boost::target(e, _graph), grid, vox);
	}
	return true;
}

/*! read graph from file
*/
bool Graph3D::read_graph(const std::string & inFileName){

	// load xml into tree and parse nodes and edges
	namespace pt = boost::property_tree;

	const std::string vertexPath = "vasculature.vertices";
	const std::string edgePath = "vasculature.edges";
	const std::string vertexName = "vertex";
	const std::string edgeName = "edge";
	pt::ptree tree;

	try{
		pt::read_xml(inFileName, tree, pt::xml_parser::trim_whitespace);
		// get vertices 
		BOOST_FOREACH(pt::ptree::value_type const& vertex, tree.get_child(vertexPath)){
			if (vertex.first == vertexName){
				pt::ptree vertexSpecTree = vertex.second;
				auto v = Coord3D_f(vertexSpecTree.get<double>("x"),
					vertexSpecTree.get<double>("y"),
					vertexSpecTree.get<double>("z"));
				add_vertex(v);
			}
		}
		// get edges
		BOOST_FOREACH(pt::ptree::value_type const& edges, tree.get_child(edgePath)){
			if (edges.first == edgeName){
				pt::ptree edgeSpecTree = edges.second;
				add_edge(edgeSpecTree.get<unsigned int>("s"),
					edgeSpecTree.get<unsigned int>("t"),
					edgeSpecTree.get<unsigned int>("d"));
			}
		}
	}
	catch (std::exception & e){
		//std::cerr << "Error loading vasculature " << std::endl;
		std::cerr << e.what() << std::endl;
		throw e;
	}
}

/*! check if vertex already exist
/*! check if vertex already exist
	valid if smaller than number of vertices
*/
bool Graph3D::valid_vertex(const unsigned int id) const{
	return id < boost::num_vertices(_graph);
}

};
