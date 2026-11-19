package track

import (
	"image"
	"image/color"
	"image/png"
	"math"
	"os"
	"path/filepath"
	"testing"
)

// TestRenderPreviews draws a top-down PNG per map (road coloured by height, start line red,
// ramps blue) when ULTIRACE_PREVIEW_DIR is set. Used to eyeball map shapes.
func TestRenderPreviews(t *testing.T) {
	dir := os.Getenv("ULTIRACE_PREVIEW_DIR")
	if dir == "" {
		t.Skip("set ULTIRACE_PREVIEW_DIR to render map previews")
	}
	tracks, _ := loadAll(t)
	for id, tr := range tracks {
		minX, minZ, maxX, maxZ, minY, maxY := math.Inf(1), math.Inf(1), math.Inf(-1), math.Inf(-1), math.Inf(1), math.Inf(-1)
		for i := 0; i < 1000; i++ {
			p := tr.At(tr.Length * float64(i) / 1000).Pos
			minX, maxX = math.Min(minX, p.X), math.Max(maxX, p.X)
			minZ, maxZ = math.Min(minZ, p.Z), math.Max(maxZ, p.Z)
			minY, maxY = math.Min(minY, p.Y), math.Max(maxY, p.Y)
		}
		const px, margin = 800, 40.0
		scale := (px - 2*margin) / math.Max(maxX-minX+30, maxZ-minZ+30)
		img := image.NewRGBA(image.Rect(0, 0, px, px))
		for i := range img.Pix {
			img.Pix[i] = 30
			if i%4 == 3 {
				img.Pix[i] = 255
			}
		}
		plot := func(x, z float64, c color.RGBA) {
			ix := int(margin + (x-minX+15)*scale)
			iz := int(margin + (z-minZ+15)*scale)
			img.SetRGBA(ix, iz, c)
		}
		steps := int(tr.Length * 4)
		for i := 0; i < steps; i++ {
			s := tr.Length * float64(i) / float64(steps)
			smp := tr.At(s)
			h := 0.0
			if maxY > minY {
				h = (smp.Pos.Y - minY) / (maxY - minY)
			}
			c := color.RGBA{uint8(90 + 165*h), uint8(200 - 120*h), 90, 255}
			for d := -smp.HalfWidth; d <= smp.HalfWidth; d += 0.5 / scale {
				w := tr.World(s, d, 0)
				plot(w.X, w.Z, c)
			}
			if s < 2 {
				for d := -smp.HalfWidth; d <= smp.HalfWidth; d += 0.2 {
					w := tr.World(s, d, 0)
					plot(w.X, w.Z, color.RGBA{255, 40, 40, 255})
				}
			}
			for _, r := range tr.Ramps {
				if s >= r.S && s <= r.S+r.Length {
					for d := -smp.HalfWidth; d <= smp.HalfWidth; d += 0.2 {
						w := tr.World(s, d, 0)
						plot(w.X, w.Z, color.RGBA{60, 120, 255, 255})
					}
				}
			}
		}
		f, err := os.Create(filepath.Join(dir, "map_"+id+".png"))
		if err != nil {
			t.Fatal(err)
		}
		if err := png.Encode(f, img); err != nil {
			t.Fatal(err)
		}
		f.Close()
	}
}
