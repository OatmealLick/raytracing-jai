#import "Basic";
#import "Math";
#import "Random";
#import "String";
Simp :: #import "Simp";
Windows :: #import "Windows";
Input :: #import "Input";
#import "Window_Creation";
#import "Machine_X64";

#load "material.jai";
#load "util.jai";
#load "time-cpu.jai";

MAX_COLOR_VALUE :: 255;

Ray :: struct {
    origin: Vector3;
    dir: Vector3;
}

at :: (using ray: Ray, t: float) -> Vector3 {
    return origin + dir * t;
}

Hittable_Kind :: enum {
    SPHERE :: 0;
}

Hittable :: struct {
    // based on this you can switch the implementations
    hittable_kind: Hittable_Kind;
    material: Material;
}

Sphere :: struct {
    #as using h: Hittable;
    hittable_kind = .SPHERE;
    
    center: Vector3;
    radius: float;
}

Hit_Record :: struct {
    p: Vector3;
    t: float;
    // those two should always be set together
    normal: Vector3;
    front_face: bool;
    material: Material;
}

state: RenderState;

hit :: (thing: *Hittable, using ray: Ray, interval: Interval) -> bool, Hit_Record {
    if #complete thing.hittable_kind == {
        case .SPHERE;
	    s := cast(*Sphere) thing;
	    oc := origin - s.center;
	    a := length_squared(dir);
	    half_b := dot(dir, oc);
	    c := length_squared(oc) - s.radius * s.radius;
	    root_squared := half_b * half_b - a * c;
	    if root_squared < 0 {
		return false, .{};
	    } else {
	        using record: Hit_Record;
		sqrtd := sqrt(root_squared);
		t_candidate := (-half_b - sqrtd) / a;

                if !interval_surrounds(interval, t_candidate) {
		    // if first root doesn't fall in range, try the other one
		    t_candidate = (-half_b + sqrtd) / a;
		    if !interval_surrounds(interval, t_candidate) return false, .{};
		}
		// if we're here than t_candidate is within range

		t = t_candidate;
		p = at(ray, t);
		material = s.material;
		normal = (p - s.center) / s.radius;

		if dot(normal, dir) > 0.0 {
		    normal = -normal;
		    front_face = false;
		} else {
		    front_face = true;
		}

		return true, record;
	    }
	case;
	    log_error("Can't raycast with thing of kind %", thing.hittable_kind);
	    return false, .{};
    }
}

hit_closest :: (hittables: [] *Hittable, using ray: Ray, interval: Interval) -> bool, Hit_Record {
    r: Hit_Record;
    any_success := false;
    closest_t := interval.max;
    for hittables {
        success, record := hit(it, ray, .{min=interval.min, max=closest_t});
	if success {
	    any_success = true;
	    if record.t < closest_t {
		closest_t = record.t;
		r = record;
	    }
	}
    }
    return any_success, r;
}

ray_color :: (ray: Ray, hittables: [] *Hittable, depth: int) -> Vector3 {
    if depth <= 0 return .{};

    success, r := hit_closest(hittables, ray, DEFAULT_INTERVAL);
    if success {
	// todo consider stack variables instead of allocations
	ray_out := New(Ray);
	attenuation := New(Vector3);
	success := scatter(ray, r, ray_out, attenuation);
	return ifx success then attenuation * ray_color(ray_out, hittables, depth - 1) else .{};
    } else {
        // draw sky
	unit_dir := unit_vector(ray.dir);
	a := 0.5 * (unit_dir.y + 1.0);
	return (1.0 - a) * ONE + a * .{0.5, 0.7, 1.0};
    }
}

generate_random_pixel_offset :: (pixel_delta_u: Vector3, pixel_delta_v: Vector3) -> Vector3 {
    px := -0.5 * random_get_zero_to_one_open();
    py := -0.5 * random_get_zero_to_one_open();
    return px * pixel_delta_u + py * pixel_delta_v;
}

linear_to_gamma :: (value: float) -> float {
    return sqrt(value);
}

defocus_disk_sample :: (using c: Camera) -> Vector3 {
    offset := unit_vector(Vector3.{
	random_get_within_range(-1.0, 1.0),
	random_get_within_range(-1.0, 1.0),
	0
    });
    return lookfrom + (offset.x * defocus_disk_u) + (offset.y * defocus_disk_v);
}

to_rgb :: (color: Vector3) -> u8, u8, u8 {
    r := cast(u8) (linear_to_gamma(color.x) * MAX_COLOR_VALUE);
    g := cast(u8) (linear_to_gamma(color.y) * MAX_COLOR_VALUE);
    b := cast(u8) (linear_to_gamma(color.z) * MAX_COLOR_VALUE);
    return r, g, b;
}

RenderState :: struct {
    quit := false;
    width: int;
    height: int;
    window: Window_Type;
    texture: Simp.Texture;
}

initialize_rendering :: (width: int, height: int) -> RenderState {
    Windows.SetProcessDPIAware();
    // Windows is very bad at thread-switching by default unless you do this. Sad.
    Windows.timeBeginPeriod(1);
    window := create_window(width, height, "Raytracing Output");

    Simp.set_render_target(window);

    state := RenderState.{};
    state.width = width;
    state.height = height;
    state.window = window;
    return state;
}

render_frame :: (using state: *RenderState) {
    Input.update_window_events();

    for Input.events_this_frame {
	if it.type == .QUIT then quit = true;

	if it.type == {
	    case .KEYBOARD;
	    if it.key_pressed && (it.key_code == .ESCAPE) {
		quit = true;
	    }
	}
    }

    Simp.clear_render_target(.15, .15, .15, 1);

    Simp.set_shader_for_images(*state.texture);
    Simp.immediate_begin();

    v2 :: (x: int, y: int) -> Vector2 {
	return make_vector2(cast(float)x, cast(float)y);
    }
    Simp.immediate_quad(v2(0, 0), v2(width, 0), v2(width, height), v2(0, height));
    Simp.immediate_flush();
    
    Simp.swap_buffers(window);
}

lo :: (format_string: string, args: .. Any) {
    log_error(format_string, ..args);
}

Camera :: struct {
    // use create_camera(...) to properly initialize
    lookfrom: Vector3;
    lookat: Vector3;
    vup: Vector3;
    vfov: int;
    defocus_angle: float;
    focus_dist: float;

    // to be set by create_camera(...)
    pixel_delta_u: Vector3;
    pixel_delta_v: Vector3;
    p00_location: Vector3;
    defocus_disk_u: Vector3;
    defocus_disk_v: Vector3;
}

create_camera :: (_lookfrom: Vector3,
		  _lookat: Vector3,
		  _vup: Vector3,
		  _vfov: int,
		  _defocus_angle: float,
		  _focus_dist: float,
		  image_width: int,
		  image_height: int) -> Camera
{
    using c: Camera = ---;
    lookfrom = _lookfrom;
    lookat = _lookat;
    vup = _vup;
    vfov = _vfov;
    defocus_angle = _defocus_angle;
    focus_dist = _focus_dist;

    theta := deg_to_rad(xx vfov);
    h := tan(theta / 2.0);
    viewport_height := 2 * h * focus_dist;
    viewport_width := viewport_height * (cast(float) image_width / image_height);

    w := unit_vector(lookfrom - lookat);
    u := unit_vector(cross(vup, w));
    v := cross(w, u);

    viewport_u := viewport_width * u;
    viewport_v := viewport_height * -v;
    pixel_delta_u = viewport_u / cast(float) image_width;
    pixel_delta_v = viewport_v / cast(float) image_height;

    p00_location = lookfrom
	- (focus_dist * w)
	- viewport_u / 2.0
	- viewport_v / 2.0
	+ pixel_delta_u / 2.0
	+ pixel_delta_v / 2.0;

    defocus_radius := focus_dist * tan(deg_to_rad(defocus_angle / 2.0));
    defocus_disk_u = u * defocus_radius;
    defocus_disk_v = v * defocus_radius;
    
    return c;
}

main :: () {
    cpu_freq := estimate_cpu_frequency();
    
    image_width := 200;
    aspect_ratio := 16.0 / 9.0;
    image_height := cast(int) (cast(float) image_width / aspect_ratio);
    samples_per_pixel := 10;
    max_depth := 10;

    using c := create_camera(
	_lookfrom = Vector3.{13, 2, 3},
	_lookat = Vector3.{0, 0, 0},
	_vup = Vector3.{0, 1, 0},
	_vfov = 20,
	_defocus_angle = 0.6,
	_focus_dist = 10.0,
	image_width=image_width,
	image_height=image_height
    );

    if image_height < 1 then image_height = 1;

    state = initialize_rendering(image_width, image_height);
    texture_data := NewArray(3 * image_width * image_height, u8);

    // material_ground := Material.{material_kind=.LAMBERTIAN, albedo=.{0.8, 0.8, 0.0}};
    // material_center := Material.{material_kind=.LAMBERTIAN, albedo=.{0.1, 0.2, 0.5}};
    // material_left   := Material.{material_kind=.DIELECTRIC, refraction=1.5};
    // material_right  := Material.{material_kind=.METAL, albedo=.{0.8, 0.6, 0.2}, fuzz=0.0};

    // ground := Sphere.{center=.{0, -100.5, -1}, radius=100, material=material_ground};
    // center := Sphere.{center=.{0, 0, -1}, radius=0.5, material=material_center};
    // left   := Sphere.{center=.{-1, 0, -1}, radius=0.5, material=material_left};
    // hollow := Sphere.{center=.{-1, 0, -1}, radius=-0.4, material=material_left};
    // right  := Sphere.{center=.{1, 0, -1}, radius=0.5, material=material_right};

    material_ground := Material.{material_kind=.LAMBERTIAN, albedo=.{0.5, 0.5, 0.5}};
    ground := Sphere.{center=.{0, -1000, -1}, radius=1000, material=material_ground};
    
    hittables: [..] *Hittable;
    array_add(*hittables, *ground);

    r :: () -> float {
	return random_get_within_range(0.0, 1.0);
    }

    rv :: random_vector;

    for a: -11..11 for b: -11..11 {
	mat := r();
	to_be_center := Vector3.{a + 0.9*r(), 0.2, b + 0.9*r()};
	if length(to_be_center - xyz(4, 0.2, 0)) > 0.9 {
	    using s := New(Sphere);
	    center=to_be_center;
	    radius=0.2;
	    if mat < 0.8 {
		albedo := rv(0, 1) * rv(0, 1);
		material=Material.{material_kind=.LAMBERTIAN, albedo=albedo};
	    } else if mat < 0.95 {
		albedo := random_vector(0.5, 1.0);
		fuzz := random_get_within_range(0.0, 0.5);
		material=Material.{material_kind=.METAL, albedo=albedo, fuzz=fuzz};
	    } else {
		material=Material.{material_kind=.DIELECTRIC, refraction=1.5};
	    }
	    array_add(*hittables, s);
	}
    }

    m1 := Material.{material_kind=.DIELECTRIC, refraction=1.5};
    s1 := Sphere.{center=.{0, 1, 0}, radius=1.0, material=m1};
    array_add(*hittables, *s1);

    m2 := Material.{material_kind=.LAMBERTIAN, albedo=.{0.4, 0.2, 0.1}};
    s2 := Sphere.{center=.{-4, 1, 0}, radius=1.0, material=m2};
    array_add(*hittables, *s2);

    m3 := Material.{material_kind=.METAL, albedo=.{0.7, 0.6, 0.5}, fuzz=0.0};
    s3 := Sphere.{center=.{4, 1, 0}, radius=1.0, material=m3};
    array_add(*hittables, *s3);

    start := rdtsc();

    for y: 0..image_height - 1 {
        // log("Scanlines remaining %", image_height - 1 - y);

	for x: 0..image_width - 1 {
	    result_color: Vector3;

	    for 0..samples_per_pixel-1 {
		pixel_location := p00_location
		    + (cast(float) y * pixel_delta_v)
		    + (cast(float) x * pixel_delta_u);
		pixel_offset := generate_random_pixel_offset(
		    pixel_delta_u, pixel_delta_v);

		ray_origin := ifx defocus_angle <= 0 then lookfrom else defocus_disk_sample(c);
		ray_direction := (pixel_location + pixel_offset) - ray_origin;
		r := Ray.{ray_origin, ray_direction};
		result_color += ray_color(r, hittables, max_depth);
	    }
	    r, g, b := to_rgb(result_color / cast(float) samples_per_pixel);
	    texture_data[3 * (y * image_width + x)] = r;
	    texture_data[3 * (y * image_width + x) + 1] = g;
	    texture_data[3 * (y * image_width + x) + 2] = b;
	}
    }

    end := rdtsc();

    // log("Done.");

    elapsed_ticks := end - start;
    log("Total ticks %, (% seconds), cpu_freq %", elapsed_ticks, cast(float)elapsed_ticks / cpu_freq, cpu_freq);
    log("Image width %, samples per pixel %, max depth %", image_width, samples_per_pixel, max_depth);

    bitmap: Simp.Bitmap;
    format: Simp.Texture_Format = .RGB8;
    // no need for copy
    Simp.bitmap_alloc(*bitmap, xx image_width, xx image_height, format);
    memcpy(bitmap.data.data, texture_data.data, bitmap.stride*bitmap.height);

    success := Simp.texture_load_from_bitmap(*state.texture, *bitmap);

    while !state.quit {
	render_frame(*state);
    }
    sleep_milliseconds(50);
}

#scope_file

deg_to_rad :: (v: $T) -> float {
    return (v * TAU) / 360.0;
}
