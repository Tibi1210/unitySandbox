using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class HelloWorldScript : MonoBehaviour
{

    private Material material;

    // Start is called before the first frame update
    void Start()
    {
        material = GetComponent<Renderer>().material;
    }

    // Update is called once per frame
    void Update()
    {
        var color = material.GetColor("_BaseColor");

        float hue, sat, val;
        Color.RGBToHSV(color, out hue, out sat, out val);
        hue = (Time.time * 0.25f) % 1.0f;

        color = Color.HSVToRGB(hue, sat, val);
        material.SetColor("_BaseColor", color);

    }
}
