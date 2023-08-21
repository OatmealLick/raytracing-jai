#import "Basic";

Material :: struct {
    material_kind: Material_Kind;
    albedo: Vector3;
    fuzz := 1.0; // metal materials only
    refraction := 1.0; // index of refraction, dielectric only
}

Material_Kind :: enum {
    LAMBERTIAN :: 0;
    METAL :: 1;
    DIELECTRIC :: 2;
}

/*
    ray_in: incoming ray that hit the surface
    ray_out: scattered ray, the result of the hit
*/
scatter :: (ray_in: Ray,
	    r: Hit_Record,
	    ray_out: *Ray,
	    attenuation: *Vector3) -> bool {
    using r.material;
    if #complete material_kind == {
	case .LAMBERTIAN; {
	    direction := r.normal + random_on_same_hemisphere(r.normal);
	    if near_zero(direction) direction = r.normal;
	    ray_out.origin = r.p;
	    ray_out.dir = direction;
	    attenuation.x = albedo.x;
	    attenuation.y = albedo.y;
	    attenuation.z = albedo.z;
	    return true;
	}
	case .METAL; {
	    reflected := reflect(unit_vector(ray_in.dir), r.normal);
	    scattered_dir := reflected + fuzz * random_unit_vector();
	    ray_out.origin = r.p;
	    ray_out.dir = scattered_dir;
	    attenuation.x = albedo.x;
	    attenuation.y = albedo.y;
	    attenuation.z = albedo.z;
	    return dot(scattered_dir, r.normal) > 0;
	}
	case .DIELECTRIC; {
	    refraction_ratio := ifx r.front_face then (1.0 / refraction) else refraction;
	    unit_direction := unit_vector(ray_in.dir);

	    cos_theta := min(dot(-unit_direction, r.normal), 1.0);
	    sin_theta := sqrt(1.0 - cos_theta * cos_theta);

	    can_refract_p1 := refraction_ratio * sin_theta <= 1.0;
	    can_refract_p2 := !(reflectance(cos_theta, refraction_ratio) > random_get_zero_to_one_open());
	    direction: Vector3 = ---;

	    if can_refract_p1 && can_refract_p2 {
		direction = refract(unit_direction, r.normal, refraction_ratio);
	    } else {
		direction = reflect(unit_direction, r.normal);
	    }

	    ray_out.origin = r.p;
	    ray_out.dir = direction;
	    attenuation.x = 1.0;
	    attenuation.y = 1.0;
	    attenuation.z = 1.0;
	    return true;
	}
    }
}

#scope_file

near_zero :: (v: Vector3) -> bool {
    return abs(v.x) < EPS && abs(v.y) < EPS && abs(v.z) < EPS;
}

reflectance :: (cosine: float, ref_idx: float) -> float {
    r0 := (1-ref_idx) / (1+ref_idx);
    r0 = r0 * r0;
    return r0 + (1-r0) * pow((1 - cosine), 5);
}
