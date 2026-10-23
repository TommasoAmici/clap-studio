import Accelerate
import Foundation

/// PCA fitted by streaming over chunks, so 100k x 2048 embeddings never sit in memory at once.
public struct PCAModel: Sendable {
    public let dim: Int
    public let k: Int
    public let mean: [Float]
    /// k x dim, row-major, rows ordered by decreasing variance.
    public let components: [Float]

    public init(dim: Int, k: Int, mean: [Float], components: [Float]) {
        self.dim = dim; self.k = k; self.mean = mean; self.components = components
    }

    /// `forEachChunk` must call its body once per chunk (rows x dim, row-major) and
    /// is invoked twice: once for the mean, once for the covariance.
    public static func fit(dim: Int, maxComponents: Int,
                           forEachChunk: (([Float], Int) -> Void) throws -> Void) throws -> PCAModel {
        var mean = [Float](repeating: 0, count: dim)
        var count = 0
        try forEachChunk { chunk, rows in
            for r in 0..<rows {
                chunk.withUnsafeBufferPointer { p in
                    vDSP_vadd(mean, 1, p.baseAddress! + r * dim, 1, &mean, 1, vDSP_Length(dim))
                }
            }
            count += rows
        }
        guard count > 1 else { throw DBError.sql("PCA needs at least two samples") }
        var inv = 1 / Float(count)
        vDSP_vsmul(mean, 1, &inv, &mean, 1, vDSP_Length(dim))

        var cov = [Float](repeating: 0, count: dim * dim)
        try forEachChunk { chunk, rows in
            var centered = chunk
            for r in 0..<rows {
                centered.withUnsafeMutableBufferPointer { p in
                    vDSP_vsub(mean, 1, p.baseAddress! + r * dim, 1, p.baseAddress! + r * dim, 1, vDSP_Length(dim))
                }
            }
            cblas_ssyrk(CblasRowMajor, CblasUpper, CblasTrans, Int32(dim), Int32(rows),
                        1, centered, Int32(dim), 1, &cov, Int32(dim))
        }
        vDSP_vsmul(cov, 1, &inv, &cov, 1, vDSP_Length(dim * dim))

        let k = max(1, min(maxComponents, dim, count - 1))
        let comps = try topEigenvectors(&cov, dim: dim, k: k)
        return PCAModel(dim: dim, k: k, mean: mean, components: comps)
    }

    /// Row-major upper triangle == column-major lower triangle, hence uplo "L".
    private static func topEigenvectors(_ matrix: inout [Float], dim: Int, k: Int) throws -> [Float] {
        var jobz = CChar(UInt8(ascii: "V")), uplo = CChar(UInt8(ascii: "L"))
        var n = __LAPACK_int(dim), lda = n, info: __LAPACK_int = 0
        var w = [Float](repeating: 0, count: dim)
        var work = [Float](repeating: 0, count: 1)
        var lwork: __LAPACK_int = -1
        ssyev_(&jobz, &uplo, &n, &matrix, &lda, &w, &work, &lwork, &info)
        lwork = __LAPACK_int(work[0])
        work = [Float](repeating: 0, count: Int(lwork))
        ssyev_(&jobz, &uplo, &n, &matrix, &lda, &w, &work, &lwork, &info)
        guard info == 0 else { throw DBError.sql("eigendecomposition failed (\(info))") }
        // Eigenvalues ascend; eigenvector j is the contiguous column j.
        var out = [Float](repeating: 0, count: k * dim)
        for r in 0..<k {
            let col = dim - 1 - r
            for i in 0..<dim { out[r * dim + i] = matrix[col * dim + i] }
        }
        return out
    }

    /// Projects rows (n x dim) to n x k and L2-normalises each row so dot product = cosine.
    public func project(_ rows: [Float], count n: Int) -> [Float] {
        var centered = rows
        for r in 0..<n {
            centered.withUnsafeMutableBufferPointer { p in
                vDSP_vsub(mean, 1, p.baseAddress! + r * dim, 1, p.baseAddress! + r * dim, 1, vDSP_Length(dim))
            }
        }
        var out = [Float](repeating: 0, count: n * k)
        cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasTrans, Int32(n), Int32(k), Int32(dim),
                    1, centered, Int32(dim), components, Int32(dim), 0, &out, Int32(k))
        for r in 0..<n {
            out.withUnsafeMutableBufferPointer { p in
                var norm: Float = 0
                vDSP_svesq(p.baseAddress! + r * k, 1, &norm, vDSP_Length(k))
                norm = sqrtf(norm)
                if norm > 1e-12 {
                    var inv = 1 / norm
                    vDSP_vsmul(p.baseAddress! + r * k, 1, &inv, p.baseAddress! + r * k, 1, vDSP_Length(k))
                }
            }
        }
        return out
    }
}
