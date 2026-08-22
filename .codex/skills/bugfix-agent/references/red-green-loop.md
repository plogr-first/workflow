# Red-Green Loop

Build the narrowest reproduction that exercises the reported path. Run it against the unpatched code and record a real RED failure. Add or place the regression check at the confirmed seam. After the minimal fix, rerun the same reproduction and record GREEN plus relevant regression results. A probe that never fails on the baseline is not a valid red-capable loop.
