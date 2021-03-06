convert{T <: HMesh}(meshtype::Type{T}, c::AABB) = T(Cube{Float32}(minimum(c), maximum(c)-minimum(c)))
function convert{T <: HMesh}(meshtype::Type{T}, c::Cube)
    ET = Float32
    xdir = Vec{3, ET}(c.width[1],0f0,0f0)
    ydir = Vec{3, ET}(0f0,c.width[2],0f0)
    zdir = Vec{3, ET}(0f0,0f0,c.width[3])
    quads = [
        Quad(c.origin + zdir,   xdir, ydir), # Top
        Quad(c.origin,          ydir, xdir), # Bottom
        Quad(c.origin + xdir,   ydir, zdir), # Right
        Quad(c.origin,          zdir, ydir), # Left
        Quad(c.origin,          xdir, zdir), # Back
        Quad(c.origin + ydir,   zdir, xdir) #Front
    ]
    merge(map(meshtype, quads))
end


function getindex{NT}(q::Quad, T::Type{Normal{3, NT}})
    normal = T(normalize(cross(q.width, q.height)))
    T[normal for i=1:4]
end

getindex{FT, IndexOffset}(q::Quad, T::Type{Face{3, FT, IndexOffset}}) = T[
    Face{3, Int, 0}(1,2,3), Face{3, Int, 0}(3,4,1)
]

getindex{ET}(q::Quad, T::Type{UV{ET}}) = T[
    T(0,0), T(0,1), T(1,1), T(1,0)
]

getindex{ET}(q::Quad, T::Type{UVW{ET}}) = T[
    q.downleft,
    q.downleft + q.height,
    q.downleft + q.width + q.height,
    q.downleft + q.width
]

getindex{UVT}(r::SimpleRectangle, T::Type{UV{UVT}}) = T[
    T(0, 0),
    T(0, 1),
    T(1, 1),
    T(1, 0)
]

getindex{FT, IndexOffset}(r::SimpleRectangle, T::Type{Face{3, FT, IndexOffset}}) = T[
    Face{3, Int, 0}(1,2,3), Face{3, Int, 0}(3,4,1)
]

convert{T <: HMesh}(meshtype::Type{T}, c::Pyramid)                      = T(c[vertextype(T)], c[facetype(T)])
getindex{FT, IndexOffset}(r::Pyramid, T::Type{Face{3, FT, IndexOffset}})  = reinterpret(T, collect(map(FT,(1:18)+IndexOffset)))


spherical{T}(theta::T, phi::T) = Point{3, T}(
    sin(theta)*cos(phi),
    sin(theta)*sin(phi),
    cos(theta)
)

function call{MT <: AbstractMesh}(::Type{MT}, s::Sphere, facets=12)
    PT, FT = vertextype(MT), facetype(MT)
    FTE    = eltype(FT)
    PTE    = eltype(PT)

    vertices      = Array(PT, facets*facets+1)
    vertices[end] = PT(0, 0, -1) #Create a vertex for last triangle fan
    for j=1:facets
        theta = PTE((pi*(j-1))/facets)
        for i=1:facets
            position           = sub2ind((facets,), j, i)
            phi                = PTE((2*pi*(i-1))/facets)
            vertices[position] = (spherical(theta, phi)*PTE(s.r))+PT(s.center)
        end
    end
    indexes          = Array(FT, facets*facets*2)
    psydo_triangle_i = length(vertices)
    index            = 1
    for j=1:facets
        for i=1:facets
            next_index = mod1(i+1, facets)
            i1 = sub2ind((facets,), j, i)
            i2 = sub2ind((facets,), j, next_index)
            i3 = (j != facets) ? sub2ind((facets,), j+1, i)          : psydo_triangle_i
            i6 = (j != facets) ? sub2ind((facets,), j+1, next_index) : psydo_triangle_i
            indexes[index]   = FT(Triangle{FTE}(i1,i2,i3)) # convert to required Face index offset
            indexes[index+1] = FT(Triangle{FTE}(i3,i2,i6))
            index += 2
        end
    end
    MT(vertices, indexes)
end
