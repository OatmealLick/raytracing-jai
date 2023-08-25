#import "Basic";
#import "Math";
#import "Random";

EPS :: 0.0001;
ONE :: Vector3.{1, 1, 1};

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

random_on_same_hemisphere :: (normal: Vector3) -> Vector3 {
    r := random_unit_vector();
    return ifx dot(normal, r) > 0.0 then r else -r;
}

reflect :: (v: Vector3, n: Vector3) -> Vector3 {
    return v - 2 * dot(v, n) * n;
}

refract :: (uv: Vector3, n: Vector3, etai_over_etat: float) -> Vector3 {
    cos_theta := min(dot(-uv, n), 1.0);
    r_out_perp := etai_over_etat * (uv + cos_theta * n);
    r_out_parallel := -sqrt(abs(1.0 - length_squared(r_out_perp))) * n;
    return r_out_perp + r_out_parallel;
}
