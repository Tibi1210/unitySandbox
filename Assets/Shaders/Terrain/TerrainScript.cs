using System.Collections.Generic;
using Unity.Collections;
using UnityEngine;
using UnityEngine.Rendering;


[RequireComponent(typeof(MeshFilter), typeof(MeshRenderer), typeof(MeshCollider))]
public class TerrainScript : MonoBehaviour
{

    public Shader materialShader;
    public ComputeShader computeShader;
    private int FractalNoiseCS;

    //plane
    private int planeSize = 100;
    private Mesh mesh;
    private Vector3[] vertices;
    private Vector3[] normals;
    private Material objMaterial;

    private RenderTexture computeResult;

    private int GRID_DIM, resN;

    public struct OctaveParams{
        public float frequency;
        public float amplitude;
        public float lacunarity;
        public float persistence;
    }
    const int OctaveCount = 4;
    OctaveParams[] octaves = new OctaveParams[OctaveCount];

    [System.Serializable]
    public struct UI_OctaveParams{
        public float frequency;
        public float amplitude;
        public float lacunarity;
        public float persistence;
    }

    public bool updateOctave = false;
    public float baseFrequency = 1;
    [SerializeField]
    public UI_OctaveParams octave1;
    [SerializeField]
    public UI_OctaveParams octave2;
    [SerializeField]
    public UI_OctaveParams octave3;
    [SerializeField]
    public UI_OctaveParams octave4;

    private ComputeBuffer octaveBuffer;

    void FillOctaveStruct(UI_OctaveParams displaySettings, ref OctaveParams computeSettings){
        computeSettings.frequency = displaySettings.frequency;
        computeSettings.amplitude = displaySettings.amplitude;
        computeSettings.lacunarity = displaySettings.lacunarity;
        computeSettings.persistence = displaySettings.persistence;
    }
    void SetSOctaveBuffers(){
        FillOctaveStruct(octave1, ref octaves[0]);
        FillOctaveStruct(octave2, ref octaves[1]);
        FillOctaveStruct(octave3, ref octaves[2]);
        FillOctaveStruct(octave4, ref octaves[3]);
        octaveBuffer.SetData(octaves);
        computeShader.SetBuffer(FractalNoiseCS, "_Octaves", octaveBuffer);
    }
 

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

        FractalNoiseCS = computeShader.FindKernel("FractalNoiseCS");

        resN = 2048;

        GRID_DIM = getGridDimFor(FractalNoiseCS);

        computeResult = CreateRenderTex(resN, resN, 1, RenderTextureFormat.Default, true);
        octaveBuffer = new ComputeBuffer(4, 4 * sizeof(float));

        SetSOctaveBuffers();
  
        computeShader.SetTexture(FractalNoiseCS, "_Result", computeResult);
        computeShader.SetInt("_OctaveCount", OctaveCount);
        computeShader.SetFloat("_BaseFrequency", baseFrequency);
        computeShader.Dispatch(FractalNoiseCS, GRID_DIM, GRID_DIM, 1);

        CreatePlaneMesh();
        CreateMaterial();
        GetComponent<MeshCollider>().sharedMesh = mesh;


        objMaterial.SetTexture("_BaseTex", computeResult);

    }
    
    void Update()
    {
        if(updateOctave){
            SetSOctaveBuffers();

            computeShader.SetTexture(FractalNoiseCS, "_Result", computeResult);
            computeShader.SetFloat("_BaseFrequency", baseFrequency);
            computeShader.Dispatch(FractalNoiseCS, GRID_DIM, GRID_DIM, 1);
        }
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
        octaveBuffer.Dispose();
    }
}
