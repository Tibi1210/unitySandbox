using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class DissolveScript : MonoBehaviour
{


    [SerializeField] private Renderer dissolveRenderer;
    private Material material;

    // Start is called before the first frame update
    void Start()
    {
        material = dissolveRenderer.material;
    }

    // Update is called once per frame
    void Update()
    {
        material.SetVector("_PlaneOrigin", transform.position);
        material.SetVector("_PlaneNormal", transform.up);
    }
}
