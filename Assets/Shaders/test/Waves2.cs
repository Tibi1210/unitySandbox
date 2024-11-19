using Unity.Mathematics;
using UnityEngine;
using UnityEngine.Rendering;

[RequireComponent(typeof(MeshFilter), typeof(MeshRenderer))]
public class Waves2 : MonoBehaviour
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

    [ColorUsageAttribute(false, true)]
    public Color waterColor;

    [System.Serializable]
    public struct ui_waveSettings{
        [Range(0.01f, 1.0f)]
        public float steepness;
        [Range(0.01f, 1.0f)]
        public float waveLen;
        [Range(0.001f, 1.0f)]
        public float speed;
        [Range(1,360)]
        public int direction; 
    }

    [Header("Highlight settings")]
    public float specularGloss = 400.0f;
    [Range(0.0f, 1.0f)]
    public float fresnelBias = 0.2f;
    [Range(0.0f, 3.0f)]
    public float fresnelStrength = 1.0f;
    [Range(0.0f, 20.0f)]
    public float fresnelShininess = 5.0f;
    [Range(0.0f, 5.0f)]
    public float fresnelNormalStrength = 1.0f;

    [Header("Wave one")]
    [SerializeField]
    ui_waveSettings wave1;
    [Header("Wave two")]
    [SerializeField]
    ui_waveSettings wave2;
    [Header("Wave three")]
    [SerializeField]
    ui_waveSettings wave3;
    [Header("Wave four")]
    [SerializeField]
    ui_waveSettings wave4;

    public struct waveSettings{
        public float steepness;
        public float waveLen;
        public float speed;
        public int direction; 
    }
    private const int waveNum = 4;
    waveSettings[] waves = new waveSettings[waveNum];

    private ComputeBuffer waveSettingsBuffer;

    void GetWaveSetigns(ui_waveSettings uiInput, ref waveSettings settings)
    {
        settings.waveLen = uiInput.waveLen;
        settings.steepness = uiInput.steepness;
        settings.speed = uiInput.speed;
        settings.direction = uiInput.direction;
    }
    void SetWaveSettingsBuffer(int kernel)
    {
        GetWaveSetigns(wave1, ref waves[0]);
        GetWaveSetigns(wave2, ref waves[1]);
        GetWaveSetigns(wave3, ref waves[2]);
        GetWaveSetigns(wave4, ref waves[3]);

        waveSettingsBuffer.SetData(waves);
        computeShader.SetBuffer(kernel, "_WaveSettingsBuffer", waveSettingsBuffer);
    }

    private int resN;
    private uint threadGroupSize;
    private int threadGroups;

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


    void Start()
    {
        CreatePlaneMesh();
        CreateMaterial();

        kernel = computeShader.FindKernel("CS_Wave");

        resN = 1024;

        computeShader.GetKernelThreadGroupSizes(kernel, out threadGroupSize, out _, out _);
        threadGroups = (int)((resN + (threadGroupSize - 1)) / threadGroupSize);

        waveSettingsBuffer = new ComputeBuffer(waveNum, 3 * sizeof(float) + sizeof(int));

        computeResult = CreateRenderTex(resN, resN, 2, RenderTextureFormat.ARGBHalf, true);

        computeShader.SetTexture(kernel, "_HeightMap", computeResult);
        computeShader.SetFloat("_FrameTime", Time.time);
        computeShader.SetFloat("_Resolution", resN);
        computeShader.SetInt("_WaveNum", waveNum);
        SetWaveSettingsBuffer(kernel);
        computeShader.Dispatch(kernel, threadGroups, threadGroups, 1);

        objMaterial.SetTexture("_BaseTex", computeResult);
        objMaterial.SetFloat("_GlossPower", specularGloss);
        objMaterial.SetFloat("_FresnelBias", fresnelBias);
        objMaterial.SetFloat("_FresnelStrength", fresnelStrength);
        objMaterial.SetFloat("_FresnelShininess", fresnelShininess);
        objMaterial.SetFloat("_FresnelNormalStrength", fresnelNormalStrength);
    }

    void Update()
    {
        objMaterial.SetVector("_BaseColor", waterColor);

        computeShader.SetFloat("_FrameTime", Time.time);
        SetWaveSettingsBuffer(kernel);
        computeShader.Dispatch(kernel, threadGroups, threadGroups, 1);
        objMaterial.SetTexture("_BaseTex", computeResult);
        objMaterial.SetFloat("_GlossPower", specularGloss);
        objMaterial.SetFloat("_FresnelBias", fresnelBias);
        objMaterial.SetFloat("_FresnelStrength", fresnelStrength);
        objMaterial.SetFloat("_FresnelShininess", fresnelShininess);
        objMaterial.SetFloat("_FresnelNormalStrength", fresnelNormalStrength);



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
        waveSettingsBuffer.Dispose();
    }
}
