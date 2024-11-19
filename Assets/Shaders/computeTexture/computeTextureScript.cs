using UnityEngine;
using UnityEngine.Rendering;


[RequireComponent(typeof(MeshFilter), typeof(MeshRenderer))]
public class computeTextureScript : MonoBehaviour
{

    public Shader materialShader;
    public ComputeShader computeShader;
    private int kernel;

    //plane
    public int planeSize = 100;
    private Mesh mesh;
    private Vector3[] vertices;
    private Vector3[] normals;
    private Material objMaterial;

    private RenderTexture computeResult;

    [ColorUsageAttribute(false, true)]
    public Color waterColor;
    [Range(1, 64)]
    public int tessAmount = 1;

    [System.Serializable]
    public struct ui_waveSettings{
        [Range(0, 10)]
        public int strength;
        [Range(0, 10)]
        public int speed;
        [Range(0, 10)]
        public int amplitude;
        [Range(0, 10)]
        public int phase;
    }
    [Header("Wave one")]
    [SerializeField]
    ui_waveSettings wave1;
    [Header("Wave two")]
    [SerializeField]
    ui_waveSettings wave2;

    public struct waveSettings{
        public int strength;
        public int speed;
        public int amplitude;
        public int phase;
    }
    private const int waveNum = 2;
    waveSettings[] waves = new waveSettings[waveNum];

    private ComputeBuffer waveSettingsBuffer;

    void getWaveSetigns(ui_waveSettings uiInput, waveSettings settings)
    {
        uiInput.strength = settings.strength;
        uiInput.speed = settings.speed;
        uiInput.amplitude = settings.amplitude;
        uiInput.phase = settings.phase;
    }
    void setWaveSettingsBuffer(int kernel)
    {
        getWaveSetigns(wave1, waves[0]);
        getWaveSetigns(wave2, waves[1]);

        waveSettingsBuffer.SetData(waves);
        computeShader.SetBuffer(kernel, "_WaveSettingsBuffer", waveSettingsBuffer);
    }

    private int threadGroupsX, threadGroupsY, resN;

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

        kernel = computeShader.FindKernel("CSMain");

        resN = 1024;
        threadGroupsX = Mathf.CeilToInt(resN / 8.0f);
        threadGroupsY = Mathf.CeilToInt(resN / 8.0f);

        waveSettingsBuffer = new ComputeBuffer(waveNum, 4 * sizeof(int));

        computeResult = CreateRenderTex(resN, resN, 1, RenderTextureFormat.Default, true);
        computeShader.SetTexture(kernel, "_Result", computeResult);
        setWaveSettingsBuffer(kernel);
        computeShader.Dispatch(kernel, threadGroupsX, threadGroupsY, 1);
    }

    void Update()
    {

        objMaterial.SetTexture("_BaseTex", computeResult);
        objMaterial.SetVector("_BaseColor", waterColor);

        objMaterial.SetFloat("_WaveStrength", wave1.strength);
        objMaterial.SetInt("_WaveSpeed", wave1.speed);
        objMaterial.SetInt("_WaveAmplitude", wave1.amplitude);
        objMaterial.SetInt("_WavePhase", wave1.phase);

        objMaterial.SetInt("_TessAmount", tessAmount);


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
