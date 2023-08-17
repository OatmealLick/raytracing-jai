#import "Basic";
#import "Math";
#import "Random";

EPS :: 0.0001;
ONE :: Vector3.{1, 1, 1};

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
    kind: Hittable_Kind;
}

Sphere :: struct {
    #as using h: Hittable;
    kind = .SPHERE;
    
    center: Vector3;
    radius: float;
}

Hit_Record :: struct {
    p: Vector3;
    t: float;
    // those two should always be set together
    normal: Vector3;
    front_face: bool;
}

Interval :: struct {
    min: float;
    max: float;
}

EMPTY_INTERVAL :: Interval.{min=FLOAT32_MAX, max=FLOAT32_MIN};
UNIVERSE_INTERVAL :: Interval.{min=FLOAT32_MIN, max=FLOAT32_MAX};
DEFAULT_INTERVAL :: Interval.{min=0.001, max=FLOAT32_MAX};

interval_contains :: (using interval: Interval, value: float) -> bool {
    return value >= min && value <= max;
}

interval_surrounds :: (using interval: Interval, value: float) -> bool {
    return value > min && value < max;
}

interval_clamp :: (using interval: Interval, value: float) -> float {
    if value > max return max;
    else if value < min return min;
    else return value;
}

random :: (min: float, max: float) -> float {
    return min + (max - min) * random_get_zero_to_one();
}

random_vector :: (min: float, max: float) -> Vector3 {
    return .{
        random(min, max),
        random(min, max),
        random(min, max) };
}

random_unit_vector :: () -> Vector3 {
    v := random_vector(-1, 1);
    return v / length(v);
}

hit :: (thing: *Hittable, using ray: Ray, interval: Interval) -> bool, Hit_Record {
    if #complete thing.kind == {
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
		n := (p - s.center) / s.radius;
		outward_normal := (n + ONE) * 0.5;
		// consider not just using n not outward normal

		if dot(outward_normal, dir) > 0.0 {
		    normal = -outward_normal;
		    front_face = false;
		} else {
		    normal = outward_normal;
		    front_face = true;
		}

		return true, record;
	    }
	case;
	    log_error("Can't raycast with thing of kind %", thing.kind);
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

random_on_same_hemisphere :: (normal: Vector3) -> Vector3 {
    r := random_unit_vector();
    return ifx dot(normal, r) > 0.0 then r else -r;
}

ray_color :: (ray: Ray, hittables: [] *Hittable) -> Vector3 {
    success, r := hit_closest(hittables, ray, DEFAULT_INTERVAL);
    if success {
	target := r.p + r.normal + random_on_same_hemisphere(r.normal);
	return 0.5 * ray_color(.{r.p, target - r.p}, hittables);
        //return hit_record.normal;
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

main :: () {
    image_width := 400;
    aspect_ratio := 16.0 / 9.0;
    image_height := cast(int) (cast(float) image_width / aspect_ratio);
    samples_per_pixel := 10;

    if image_height < 1 then image_height = 1;

    focal_length := 1.0;
    viewport_height := 2.0;
    viewport_width := viewport_height * (cast(float) image_width / image_height);
    camera_center := Vector3.{0.0, 0.0, 0.0};

    viewport_u := Vector3.{viewport_width, 0.0, 0.0};
    viewport_v := Vector3.{0.0, -viewport_height, 0.0};
    pixel_delta_u := viewport_u / cast(float) image_width;
    pixel_delta_v := viewport_v / cast(float) image_height;

    p00_location := camera_center
	- .{0.0, 0.0, focal_length} 
	- viewport_u / 2.0
	- viewport_v / 2.0
	+ pixel_delta_u / 2.0
	+ pixel_delta_v / 2.0;

    sphere := Sphere.{center=.{0, 0, -1}, radius=0.5};
    ground := Sphere.{center=.{0, -100.5, -1}, radius=100};
    hittables: [] *Hittable = .[*sphere, *ground];

    print("P3\n% %\n%\n", image_width, image_height, 255);
    for y: 0..image_height - 1 {
        lo("Scanlines remaining %", image_height - 1 - y);

	for x: 0..image_width - 1 {
	    result_color: Vector3; // make sure its zero

	    for 0..samples_per_pixel-1 {
		pixel_location := p00_location
		    + (cast(float) y * pixel_delta_v)
		    + (cast(float) x * pixel_delta_u);
		pixel_offset := generate_random_pixel_offset(
		    pixel_delta_u, pixel_delta_v);

		ray_direction := (pixel_location + pixel_offset) - camera_center;
		r := Ray.{camera_center, ray_direction};
		result_color += ray_color(r, hittables);
	    }
	    print_color(result_color / cast(float) samples_per_pixel);
	}
    }

    lo("Done.");
}

print_color :: (color: Vector3) {
    // vector should have values from [0.0, 1.0]
    // assert(color.x >= 0 && color.x <= 1.0, "Color component is not within range, color %", color);
    // assert(color.y >= 0 && color.y <= 1.0, "Color component is not within range, color %", color);
    // assert(color.z >= 0 && color.z <= 1.0, "Color component is not within range, color %", color);
    max_color_value := 255;
    r := cast(int) (color.x * max_color_value);
    g := cast(int) (color.y * max_color_value);
    b := cast(int) (color.z * max_color_value);
    print("% % %\n", r, g, b);
}

lo :: (format_string: string, args: .. Any) {
    log_error(format_string, ..args);
}
