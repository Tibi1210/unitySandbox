using UnityEngine;
using UnityEngine.Rendering;


[RequireComponent(typeof(MeshFilter), typeof(MeshRenderer), typeof(MeshCollider))]
public class TerrainScript : MonoBehaviour
{

    public Shader materialShader;
    public ComputeShader computeShader;
    private int kernel;

    //plane
    private int planeSize = 100;
    private Mesh mesh;
    private Vector3[] vertices;
    private Vector3[] normals;
    private Material objMaterial;

    public RenderTexture computeResult;

    private int GRID_DIM, resN;

    public Vector4 _Scale = new Vector4(1.0f,1.0f,1.0f,1.0f);
    [Range(1.0f,100.0f)]
    public float _HeightScale; 
    [Range(0.01f,1.0f)]
    public float _Amplitude;
    [Range(1,20)]
    public int _Octaves;
    [Range(0, 100000)]
    public int _Seed = 0;
    public Vector4 _Scale2 = new Vector4(1.0f,1.0f,1.0f,1.0f);
 

    RenderTexture CreateRenderTex(int width, int height, int depth, RenderTextureFormat format, bool useMips)
    {
        RenderTexture rt = new RenderTexture(width, height, 0, format, RenderTextureReadWrite.Linear);
        rt.dimension = TextureDimension.Tex2DArray;
        rt.filterMode = FilterMode.Bilinear;
        rt.wrapMode = TextureWrapMode.Repeat;
        rt.enableRandomWrite = true;
        rt.volumeDepth = depth;
        rt.useMipMap = useMips;
        rt.autoGenerateMips = false;
        rt.anisoLevel = 16;
        rt.Create();

        return rt;
    }

    private void CreatePlaneMesh()
    {
        mesh = GetComponent<MeshFilter>().mesh = new Mesh();

        mesh.name = "mesh";

        float halfLength = planeSize * 0.5f;
        int sideVertCount = planeSize * 2;

        vertices = new Vector3[(sideVertCount + 1) * (sideVertCount + 1)];
        Vector2[] uv = new Vector2[vertices.Length];
        Vector4[] tangents = new Vector4[vertices.Length];
        Vector4 tangent = new Vector4(1f, 0f, 0f, -1f);

        for (int i = 0, x = 0; x <= sideVertCount; ++x)
        {
            for (int z = 0; z <= sideVertCount; ++z, ++i)
            {
                vertices[i] = new Vector3(((float)x / sideVertCount * planeSize) - halfLength, 0, ((float)z / sideVertCount * planeSize) - halfLength);
                uv[i] = new Vector2((float)x / sideVertCount, (float)z / sideVertCount);
                tangents[i] = tangent;
            }
        }

        mesh.vertices = vertices;
        mesh.uv = uv;
        mesh.tangents = tangents;

        int[] triangles = new int[sideVertCount * sideVertCount * 6];

        for (int ti = 0, vi = 0, x = 0; x < sideVertCount; ++vi, ++x)
        {
            for (int z = 0; z < sideVertCount; ti += 6, ++vi, ++z)
            {
                triangles[ti] = vi;
                triangles[ti + 1] = vi + 1;
                triangles[ti + 2] = vi + sideVertCount + 2;
                triangles[ti + 3] = vi;
                triangles[ti + 4] = vi + sideVertCount + 2;
                triangles[ti + 5] = vi + sideVertCount + 1;
            }
        }

        mesh.SetTriangles(triangles, 0);
        mesh.RecalculateNormals();
        mesh.RecalculateBounds();
        normals = mesh.normals;
    }

    void CreateMaterial()
    {
        if (materialShader == null) return;

        objMaterial = new Material(materialShader);

        MeshRenderer renderer = GetComponent<MeshRenderer>();

        renderer.material = objMaterial;
        
    }
    int getGridDimFor(int kernelIdx){
        computeShader.GetKernelThreadGroupSizes(kernelIdx, out uint BLOCK_DIM, out _, out _);
        return (int)((resN + (BLOCK_DIM - 1)) / BLOCK_DIM);
    }

    void Start()
    {
        CreatePlaneMesh();
        CreateMaterial();
        GetComponent<MeshCollider>().sharedMesh = mesh;

        kernel = computeShader.FindKernel("CSMain");

        resN = 2048;

        GRID_DIM = getGridDimFor(kernel);


        computeResult = CreateRenderTex(resN, resN, 4, RenderTextureFormat.Default, true);
        computeShader.SetTexture(kernel, "_Result", computeResult);
        computeShader.SetVector("_Scale", _Scale);
        computeShader.SetFloat("_Amplitude", _Amplitude);
        computeShader.SetInt("_Octaves", _Octaves);
        computeShader.SetInt("_Seed", _Seed);
        computeShader.Dispatch(kernel, GRID_DIM, GRID_DIM, 1);

        objMaterial.SetTexture("_BaseTex", computeResult);
        objMaterial.SetFloat("_HeightScale", _HeightScale);
        objMaterial.SetVector("_Scale2", _Scale2);
    }

    void Update()
    {
        computeShader.SetTexture(kernel, "_Result", computeResult);
        computeShader.SetVector("_Scale", _Scale);
        computeShader.SetFloat("_Amplitude", _Amplitude);
        computeShader.SetInt("_Octaves", _Octaves);
        computeShader.SetInt("_Seed", _Seed);
        computeShader.Dispatch(kernel, GRID_DIM, GRID_DIM, 1);
        objMaterial.SetTexture("_BaseTex", computeResult);
        objMaterial.SetFloat("_HeightScale", _HeightScale);
        objMaterial.SetVector("_Scale2", _Scale2);
    }

    void OnDisable()
    {
        if (objMaterial != null)
        {
            Destroy(objMaterial);
            objMaterial = null;
        }

        if (mesh != null)
        {
            Destroy(mesh);
            mesh = null;
            vertices = null;
            normals = null;
        }

        Destroy(computeResult);
    }
}
