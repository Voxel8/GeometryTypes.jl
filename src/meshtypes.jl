for s in enumerate((:vertextype, :facetype, :normaltype,
                       :texturecoordinatetype, :colortype))
    @eval begin
        $(s[2]){T<:HomogenousMesh}(t::Type{T}) = t.parameters[$(s[1])]
        $(s[2])(mesh::HomogenousMesh) = $(s[2])(typeof(mesh))
    end
end

hasvertices(msh) = vertextype(msh) != Void
hasfaces(msh) = facetype(msh) != Void
hasnormals(msh) = normaltype(msh) != Void
hastexturecoordinates(msh) = texturecoordinatetype(msh) != Void
hascolors(msh) = colortype(msh) != Void



vertices(msh) = msh.vertices
faces(msh) = msh.faces
normals(msh) = msh.normals
texturecoordinates(msh) = msh.texturecoordinates
colors(msh) = msh.color


# Bad, bad name! But it's a little tricky to filter out faces and verts from the attributes, after get_attribute
attributes_noVF(m::AbstractMesh) = filter((key,val) -> (val != nothing && val != Void[]), Dict{Symbol, Any}(map(field->(field => m.(field)), fieldnames(typeof(m))[3:end])))
#Gets all non Void attributes from a mesh in form of a Dict fieldname => value
attributes(m::AbstractMesh) = filter((key,val) -> (val != nothing && val != Void[]), all_attributes(m))
#Gets all non Void attributes types from a mesh type fieldname => ValueType
attributes{M <: HMesh}(m::Type{M}) = filter((key,val) -> (val != Void && val != Vector{Void}), all_attributes(M))

all_attributes{M <: HMesh}(m::Type{M}) = Dict{Symbol, Any}(map(field -> (field => fieldtype(M, field)), fieldnames(M)))
all_attributes{M <: HMesh}(m::M) = Dict{Symbol, Any}(map(field -> (field => getfield(m, field)),  fieldnames(M)))

# Needed to not get into an stack overflow
convert{HM1 <: HMesh}(::Type{HM1}, mesh::HM1) = mesh

# Uses getindex to get all the converted attributes from the meshtype and
# creates a new mesh with the desired attributes from the converted attributs
# Getindex can be defined for any arbitrary geometric type or exotic mesh type.
# This way, we can make sure, that you can convert most of the meshes from one type to the other
# with minimal code.
function convert{HM1 <: HMesh}(::Type{HM1}, any::Union{AbstractMesh, GeometryPrimitive})
    result = Dict{Symbol, Any}()
    for (field, target_type) in zip(fieldnames(HM1), HM1.parameters)
        if target_type != Void
            result[field] = any[target_type]
        end
    end
    HM1(result)
end


#Should be:
#function call{M <: HMesh, VT <: Point, FT <: Face}(::Type{M}, vertices::Vector{VT}, faces::Vector{FT})
# Haven't gotten around to implement the types correctly with abstract types in FixedSizeArrays
function call{M <: HMesh, VT, FT <: Face}(::Type{M}, vertices::Vector{Point{3, VT}}, faces::Vector{FT})
    msh = PlainMesh{VT, FT}(vertices=vertices, faces=faces)
    convert(M, msh)
end
get_default(x::Union{Type, TypeVar}) = nothing
get_default{X <: Array}(x::Type{X}) = Void[]

# generic constructor for abstract HomogenousMesh, infering the types from the keywords (which have to match the field names)
# some problems with the dispatch forced me to use this method name... need to further investigate this
function homogenousmesh(attribs::Dict{Symbol, Any})
    newfields = []
    for name in fieldnames(HMesh)
        push!(newfields, get(attribs, name, get_default(fieldtype(HMesh, name))))
    end
    HomogenousMesh(newfields...)
end

# Creates a mesh from keyword arguments, which have to match the field types of the given concrete mesh
call{M <: HMesh}(::Type{M}; kw_args...) = M(Dict{Symbol, Any}(kw_args))

# Creates a new mesh from a dict of fieldname => value and converts the types to the given meshtype
function call{M <: HMesh}(::Type{M}, attribs::Dict{Symbol, Any})
    newfields = map(zip(fieldnames(HomogenousMesh), M.parameters)) do field_target_type
        field, target_type = field_target_type
        default = fieldtype(HomogenousMesh, field) <: Vector ? Array(target_type, 0) : target_type
        default = default == Void ? nothing : default
        get(attribs, field, default)
    end
    HomogenousMesh(newfields...)
end

#Creates a new mesh from an old one, with changed attributes given by the keyword arguments
function call{M <: HMesh}(::Type{M}, mesh::AbstractMesh, attributes::Dict{Symbol, Any})
    newfields = map(fieldnames(HomogenousMesh)) do field
        get(attributes, field, mesh.(field))
    end
    HomogenousMesh(newfields...)
end

#Creates a new mesh from an old one, with a new constant attribute (like a color)
function call{HM <: HMesh, ConstAttrib}(::Type{HM}, mesh::AbstractMesh, constattrib::ConstAttrib)
    result = Dict{Symbol, Any}()
    for (field, target_type) in zip(fieldnames(HM), HM.parameters)
        if target_type <: ConstAttrib
            result[field] = constattrib
        elseif target_type != Void
            result[field] = mesh[target_type]
        end
    end
    HM(result)
end
function add_attribute(m::AbstractMesh, attribute)
    attribs = attributes(m) # get all attribute values as a Dict fieldname => value
    attribs[:color] = attribute # color will probably be renamed to attribute. not sure yet...
    homogenousmesh(attribs)
end

#Creates a new mesh from a pair of any and a const attribute
function call{HM <: HMesh, ConstAttrib}(::Type{HM}, x::Tuple{Any, ConstAttrib})
    any, const_attribute = x
    add_attribute(HM(any), const_attribute)
end
# Getindex methods, for converted indexing into the mesh
# Define getindex for your own meshtype, to easily convert it to Homogenous attributes

#Gets the normal attribute to a mesh
function getindex{VT}(mesh::HMesh, T::Type{Point{3, VT}})
    vts = mesh.vertices
    eltype(vts) == T       && return vts
    eltype(vts) <: Point   && return map(T, vts)
end

# gets the wanted face type
function getindex{FT, Offset}(mesh::HMesh, T::Type{Face{3, FT, Offset}})
    fs = faces(mesh)
    eltype(fs) == T       && return fs
    eltype(fs) <: Face{3} && return map(T, fs)
    if eltype(fs) <:  Face{4}
        convert(Vector{Face{3, FT, Offset}}, fs)
    end
    error("can't get the wanted attribute $(T) from mesh:")
end

#Gets the normal attribute to a mesh
function getindex{NT}(mesh::HMesh, T::Type{Normal{3, NT}})
    n = mesh.normals
    eltype(n) == T       && return n
    eltype(n) <: Normal{3} && return map(T, n)
    n == Void[]       && return normals(mesh.vertices, mesh.faces, T)
end

#Gets the uv attribute to a mesh, or creates it, or converts it
function getindex{UVT}(mesh::HMesh, ::Type{UV{UVT}})
    uv = mesh.texturecoordinates
    eltype(uv) == UV{UVT}           && return uv
    (eltype(uv) <: UV || eltype(uv) <: UVW) && return map(UV{UVT}, uv)
    eltype(uv) == Void           && return zeros(UV{UVT}, length(mesh.vertices))
end


#Gets the uv attribute to a mesh
function getindex{UVWT}(mesh::HMesh, ::Type{UVW{UVWT}})
    uvw = mesh.texturecoordinates
    typeof(uvw) == UVW{UVT}     && return uvw
    (isa(uvw, UV) || isa(uv, UVW))  && return map(UVW{UVWT}, uvw)
    uvw == nothing          && return zeros(UVW{UVWT}, length(mesh.vertices))
end
const DefaultColor = RGBA(0.2, 0.2, 0.2, 1.0)

#Gets the color attribute from a mesh
function getindex{T <: Color}(mesh::HMesh, ::Type{Vector{T}})
    colors = mesh.attributes
    typeof(colors) == Vector{T} && return colors
    colors == nothing           && return fill(DefaultColor, length(mesh.attribute_id))
    map(T, colors)
end

#Gets the color attribute from a mesh
function getindex{T <: Color}(mesh::HMesh, ::Type{T})
    c = mesh.color
    typeof(c) == T    && return c
    c == nothing      && return DefaultColor
    convert(T, c)
end

merge{M <: AbstractMesh}(m::Vector{M}) = merge(m...)

#Merges an arbitrary mesh. This function probably doesn't work for all types of meshes
function merge{M <: AbstractMesh}(m1::M, meshes::M...)
    v = m1.vertices
    f = m1.faces
    attribs = attributes_noVF(m1)
    for mesh in meshes
        append!(f, mesh.faces + length(v))
        append!(v, mesh.vertices)
        map(append!, values(attribs), values(attributes_noVF(mesh)))
    end
    attribs[:vertices]  = v
    attribs[:faces]     = f
    return M(attribs)
end

# A mesh with one constant attribute can be merged as an attribute mesh. Possible attributes are FSArrays
function merge{_1, _2, _3, _4, ConstAttrib <: Colorant, _5, _6}(
        m1::HMesh{_1, _2, _3, _4, ConstAttrib, _5, _6},
        meshes::HMesh{_1, _2, _3, _4, ConstAttrib, _5, _6}...
    )
    vertices     = copy(m1.vertices)
    faces        = copy(m1.faces)
    attribs      = attributes_noVF(m1)
    color_attrib = RGBA{U8}[RGBA{U8}(m1.color)]
    index        = Float32[length(color_attrib)-1 for i=1:length(m1.vertices)]
    for mesh in meshes
        append!(faces, mesh.faces + length(vertices))
        append!(vertices, mesh.vertices)
        attribsb = attributes_noVF(mesh)
        for (k,v) in attribsb
            k != :color && append!(attribs[k], v)
        end
        push!(color_attrib, mesh.color)
        append!(index, Float32[length(color_attrib)-1 for i=1:length(mesh.vertices)])
    end
    delete!(attribs, :color)
    attribs[:vertices]      = vertices
    attribs[:faces]         = faces
    attribs[:attributes]    = color_attrib
    attribs[:attribute_id]  = index
    return HMesh{_1, _2, _3, _4, Void, typeof(color_attrib), eltype(index)}(attribs)
end

# Fast but slightly ugly way to implement mesh multiplication
# This should probably go into FixedSizeArrays.jl, Vector{FSA} * FSA
immutable MeshMulFunctor{T} <: Base.Func{2}
    matrix::Mat{4,4,T}
end
call{T}(m::MeshMulFunctor{T}, vert) = Vec{3, T}(m.matrix*Vec{4, T}(vert..., 1))
function *{T}(m::Mat{4,4,T}, mesh::AbstractMesh)
    msh = deepcopy(mesh)
    map!(MeshMulFunctor(m), msh.vertices)
    msh
end

