import numpy as np
from collections import namedtuple

PolyProof = namedtuple("PolyProof", [
    "poly_commit",
    "poly_blind_commit",
    "poly_response",
    "poly_blind_respond",
    "x_blind_factors",
    "evaluation_commits",
    "evaluation_response",
    "value"
])

# Implementation of Groth09 inner product proof

q = 0x40000000000000000000000000000000224698fc0994a8dd8c46eb2100000001
K = GF(q)
a = K(0x00)
b = K(0x05)
E = EllipticCurve(K, (a, b))
G = E(0x40000000000000000000000000000000224698fc0994a8dd8c46eb2100000000, 0x02)

p = 0x40000000000000000000000000000000224698fc094cf91b992d30ed00000001
assert E.order() == p
Scalar = GF(p)

# Create some generator points. Normally we would use hash to curve.
# All these points will be generators since the curve is a cyclic group
H = E.random_element()
G_vec = [E.random_element() for _ in range(1000)]

def dot_product(x, y):
    result = None
    for x_i, y_i in zip(x, y):
        if result is None:
            result = int(x_i) * y_i
        else:
            result += int(x_i) * y_i
    return result

def poly_commit(p):
    # Sage randomly orders terms. No guarantee about ordering.
    #a = np.array(p.coefficients())
    a = np.array([p[i] for i in range(p.degree() + 1)])
    r = Scalar.random_element()
    C_x = int(r) * H + dot_product(a, G_vec)
    return (r, C_x)

def create_proof(p, r, x):
    a = np.array([p[i] for i in range(p.degree() + 1)])
    #a = np.array(p.coefficients())

    x = np.array([x**i for i in range(p.degree() + 1)])
    # Evaluate the polynomial
    z = a.dot(x)

    assert len(a) == len(x)

    # We will now construct a proof

    # Commitments

    t = Scalar.random_element()
    #r = Scalar.random_element()
    s = Scalar.random_element()

    C_z = int(t) * H + int(z) * G
    C_x = int(r) * H + dot_product(a, G_vec)
    C_y = int(s) * H + dot_product(x, G_vec)

    d_x = np.array([Scalar.random_element() for _ in range(len(x))])
    d_y = np.array([Scalar.random_element() for _ in range(len(x))])
    r_d = Scalar.random_element()
    s_d = Scalar.random_element()

    A_d = int(r_d) * H + dot_product(d_x, G_vec)
    B_d = int(s_d) * H + dot_product(d_y, G_vec)

    # (cx + d_x)(cy + d_y) = d_x d_y + c(x d_y + y d_x) + c^2 xy
    t_0 = Scalar.random_element()
    t_1 = Scalar.random_element()

    C_0 = int(t_0) * H + int(d_x.dot(d_y)) * G
    C_1 = int(t_1) * H + int(a.dot(d_y) + x.dot(d_x)) * G

    # Challenge
    # Using the Fiat-Shamir transform, we would hash the transcript

    #c = Scalar.random_element()
    c = 110

    # Responses

    f_x = c * a + d_x
    f_y = c * x + d_y
    r_x = c * r + r_d
    s_y = c * s + s_d
    t_z = c**2 * t + c * t_1 + t_0

    # Verify

    #B_d = int(s_d) * H + dot_product(d_y, G_vec)
    #C_y = int(s) * H + dot_product(x, G_vec)

    assert int(c) * C_x + A_d == int(r_x) * H + dot_product(f_x, G_vec)
    assert int(c) * C_y + B_d == int(s_y) * H + dot_product(f_y, G_vec)

    # Actual inner product check
    # Comm(f_x f_y) == e^2 C_z + c Comm(x d_y + y d_x) + Comm(d_x d_y)

    assert int(t_z) * H + int(f_x.dot(f_y)) * G == int(c**2) * C_z + int(c) * C_1 + C_0

    return PolyProof(
        poly_commit=C_x, 
        poly_blind_commit=A_d,
        poly_response=f_x,
        poly_blind_respond=r_x,
        x_blind_factors=(s_d, d_y, s),
        evaluation_commits=(C_0, C_1, C_z),
        evaluation_response=t_z,
        value=z
    )

def verify_proof(proof, x):
    C_x = proof.poly_commit
    A_d = proof.poly_blind_commit
    f_x = proof.poly_response
    r_x = proof.poly_blind_respond
    (s_d, d_y, s) = proof.x_blind_factors
    (C_0, C_1, C_z) = proof.evaluation_commits
    t_z = proof.evaluation_response
    z = proof.value

    x = np.array([x**i for i in range(len(a))])
    c = 110

    f_y = c * x + d_y
    s_y = c * s + s_d
    B_d = int(s_d) * H + dot_product(d_y, G_vec)
    C_y = int(s) * H + dot_product(x, G_vec)

    if int(c) * C_x + A_d != int(r_x) * H + dot_product(f_x, G_vec):
        return False
    if int(c) * C_y + B_d != int(s_y) * H + dot_product(f_y, G_vec):
        return False

    # Actual inner product check
    # Comm(f_x f_y) == e^2 C_z + c Comm(x d_y + y d_x) + Comm(d_x d_y)

    if int(t_z) * H + int(f_x.dot(f_y)) * G != int(c**2) * C_z + int(c) * C_1 + C_0:
        return False

    return True

R.<x> = LaurentPolynomialRing(Scalar)
a = np.array([
    Scalar(110), Scalar(56), Scalar(89), Scalar(6543), Scalar(2)
])
p = 0
for i, a_i in enumerate(a):
    p += a_i * x**i
print(p)
xx = Scalar(77)
r, commit = poly_commit(p)
proof = create_proof(p, r, xx)
assert verify_proof(proof, xx)
assert proof.poly_commit == commit
assert proof.value == p(xx)

