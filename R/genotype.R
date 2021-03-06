#============================================== read the cel files
# Definition : genotype the array. Used inside of genotypthis() function. However, given contrast and average intensity,
# the function can be used to genotype each SNP.
#
# input :
# nm : Contrast ( A allele intensity - B allele intensity ) of one probe set.
# ns : Average of one probe set.
# hint : mean and variance of each group provided by MouseDivGeno package. genotype() invoke the hint file, but if this function
#     is used separated, hint can be NULL.
# trans : transformation method to obtain the contrast intensity
#
# output :
# genotype : 1 = AA, 2 = AB, 3 = BB
# <example>
# data('MM'); data('SS');
# nm = MM[1,]; ns = SS[1,]
# geno = genotype(nm, ns, hint = NULL)
#======================================================================
genotype <- function(nm, ns, hint1, trans, logfn=NULL) {
    # logging code expects nm vector elements to be named
    if(!is.null(logfn) && is.null(names(nm))) {
        names(nm) <- paste("Sample", seq_along(nm), sep="")
    }
    
    onError <- function(e) {
        if(!is.null(logfn)) {
            logfn("caught an error in \"genotype\" function. setting all genotypes to -1")
        }
        nsize <- length(nm)
        list(geno = rep(-1, nsize), vino = rep(0, nsize), conf = rep(0, nsize))
    }
    tryCatch(.genotype(nm, ns, hint1, trans, logfn), error = onError)
}

.genotype <- function(nm, ns, hint1, trans, logfn=NULL) {
    doLog <- !is.null(logfn)
    
    hint <- rep(0, 3)
    hint[1] <- max(nm)
    hint[3] <- min(nm)
    if (length(hint1) != 0) 
        hint[2] <- hint1
    
    nsize <- length(nm)
    sampleNames <- names(nm)
    
    # The thresholds are used to determine how many and
    # what kind of genotypes we should consider for our tests.
    # (Eg: if all smaller than .3 BB or H so 2 only)
    #              <--B          H-----H         A-->
    ccsThresh <- c(-0.4, -0.3, -0.15, 0.15, 0.3, 0.4)
    maThresh  <- c(-0.8, -0.6, -0.3,  0.3,  0.6, 0.8)
    if (is.element(trans, "MA")) {
        thresh <- maThresh
    } else if(is.element(trans, "CCS")) {
        thresh <- ccsThresh
    } else {
        stop("expected transformMethod to be \"CCS\" or \"MA\"")
    }
    
    # rmid is used to remove the values that fall outside of our chosen
    # threshold. Calculated because vinos tend to be low intensity (if you only
    # use contrast dimension you get a bad clustering) note that 1st part is for
    # testing "in H range" and quantile part is testing for low intensity
    rmid <- nm >= thresh[2] & nm <= thresh[5] & ns < quantile(ns, 0.2)
    lnrmid <- sum(!rmid)
    if(doLog) {
        logfn("Performing genotyping. Intensity contrast/average values per sample:")
        for(i in seq_len(nsize)) {
            logfn("    %s: %f/%f", sampleNames[i], nm[i], ns[i])
        }
        
        if(any(rmid)) {
            logfn(paste(
                "the following samples are low-intensity and low-contrast so they",
                "will be excluded from genotype thresholding and genotype",
                "clustering:"))
            for(n in sampleNames[rmid]) {
                logfn("    %s", n)
            }
        }
    }
    
    istwo <- FALSE
    isone <- FALSE
    iig <- NULL
    #================================================ obvious one group SNPs
    if (all(nm[!rmid] < thresh[1])) {
        if(doLog) {
            logfn("sample contrasts fall below %f so all genotypes are being set to 3 (BB)", thresh[1])
        }
        
        geno <- rep(3, nsize)
        v1 <- vinotype(nm, ns, geno, logfn)
        vino <- v1$vino
        conf <- v1$conf
    } else if (all(nm[!rmid] > thresh[6])) {
        if(doLog) {
            logfn("sample contrasts are above %f so all genotypes are being set to 1 (AA)", thresh[6])
        }
        
        geno <- rep(1, nsize)
        v1 <- vinotype(nm, ns, geno, logfn)
        vino <- v1$vino
        conf <- v1$conf
    } else if (all(nm[!rmid] >= thresh[3] & nm[!rmid] <= thresh[4])) {
        if(doLog) {
            logfn("sample contrasts fall between %f and %f so all genotypes are being set to 2 (AB)", thresh[3], thresh[4])
        }
        
        geno <- rep(2, nsize)
        v1 <- vinotype(nm, ns, geno, logfn)
        vino <- v1$vino
        conf <- v1$conf
    } else if (all(nm[!rmid] <= thresh[2] | nm[!rmid] >= thresh[5])) {
        if(doLog) {
            fmtMsg <- paste(
                "sample contrasts fall outside of the range %f to %f. Negative ",
                "contrasts are set to 3 (BB) and positive contrasts are set to 1 (AA)",
                sep="")
            logfn(fmtMsg, thresh[2], thresh[5])
        }
        
        # 1,3
        geno <- rep(1, nsize)
        geno[nm < 0] <- 3
        v1 <- vinotype(nm, ns, geno, logfn)
        vino <- v1$vino
        conf <- v1$conf
    } else {
        #cat("timing section 1\n")
        #startTime <- proc.time()[3]
        
        ##============================================ obvious two groups SNPs
        if (all(nm <= thresh[5])) {
            if(doLog) {
                fmtMsg <- paste(
                    "all sample contrasts are less than or equal to %f ",
                    "so all genotypes will be set to 2 (AB) or 3 (BB)",
                    sep="")
                logfn(fmtMsg, thresh[5])
            }
            # 2,3
            istwo <- TRUE
            iig <- c(2, 3)
        }
        if (all(nm >= thresh[2])) {
            if(doLog) {
                fmtMsg <- paste(
                    "all sample contrasts are greater than or equal to %f ",
                    "so all genotypes will be set to 1 (AA) or 2 (AB)",
                    sep="")
                logfn(fmtMsg, thresh[2])
            }
            # 1,2
            istwo <- TRUE
            iig <- c(1, 2)
        }
        
        # Some background:
        #
        # x axis is 1 to -1 but y (intensity) is typically around 8 to 11.
        # horizontal is much bigger than vertical
        # ns / (max(ns) - min(ns)) is used for scaling to adjust for this
        adata <- cbind(nm, ns/(max(ns) - min(ns)))
        nsize <- length(nm)
        #======== test 2 ====== based on one dimension at this time rather than two
        #startTime <- proc.time()[3]
        
        emResult <- .em2Genos(c(hint[1], hint[3]), nm[!rmid])
        T <- round(emResult$T, 4)
        tgeno2 <- rep(-1, nsize)
        geno2 <- rep(-1, lnrmid)
        
        # ig => based on T give group membership by comparing two probabilities
        #       (bigger number gets group)
        #       also make sure that T is big enough (don't just pick the biggest)
        #       value is 1,2 or 2,1
        ig <- order(emResult$tau, decreasing = TRUE)
        
        # if 2nd grp is bigger ii is 2, otherwise 1
        ii <- ig[1]
        
        # assign membership if group has a bigger probability
        # T => sum of grp 1 + grp 2 is  1 which allows us to use 0.5 as a basis
        # for finding the most probable group 
        geno2[T[, ii] >= median(T[T[, ig[2]] < 0.5, ii])] <- ii
        ii <- ig[2]
        
        # geno2 == -1 indicates that geno still has no group membership
        tt <- table(T[geno2 == -1, ii])
        
        # Sort from highest to lowest probability
        stt <- sort(tt, decreasing = TRUE)[1]
        th <- sort(as.numeric(names(tt[tt == stt])), decreasing = TRUE)[1]
        
        # give membership to the second group if the probability is high enough
        geno2[geno2 == -1 & T[, ii] >= min(max(T[, ii]), max(median(T[T[, ig[1]] < 0.5, ii]), th))] <- ii
        tgeno2[!rmid] <- geno2
        if (length(unique(tgeno2[tgeno2 != -1])) == 1) {
            
            # test for 3 group case
            isone <- TRUE
            mm <- median(nm)
            if (mm > thresh[5]) {
                geno <- rep(1, nsize)
            } else if (mm < thresh[2]) {
                geno <- rep(3, nsize)
            } else {
                geno <- rep(2, nsize)
            }
            
            if(doLog) {
                fmtMsg <- paste(
                    "the two state EM was only able to assign a single genotype group. ",
                    "The contrast average is %f so genotypes have been set to %i",
                    sep="")
                logfn(fmtMsg, mm, geno[1])
            }
            
            if (istwo) {
                v1 <- vinotype(nm, ns, geno, logfn)
                vino <- v1$vino
                conf <- v1$conf
            }
        } else {
            noCalls <- tgeno2 == -1
            if (any(noCalls)) {
                # use vdist to give membership
                tgeno2 <- .vdist(adata[, 1], adata[, 2] / 5, tgeno2)
                if(doLog) {
                    logfn("used vdist function to assign missing genotypes as follows:")
                    for(i in which(noCalls)) {
                        logfn("    %s: %i", sampleNames[i], tgeno2[i])
                    }
                }
            }
            
            tscore2 <- silhouette(match(tgeno2[!rmid], unique(tgeno2[!rmid])), dist(nm[!rmid]))
            if(any(is.na(tscore2))) stop("Internal Error: silhouette score is NA")
            
            if (istwo) {
                # test if it's one group or two group
                geno <- .test12(tscore2, nm, tgeno2, rmid, thresh, iig, nsize, logfn)
                v1 <- vinotype(nm, ns, geno, logfn)
                vino <- v1$vino
                conf <- v1$conf
            }
        }
        #cat(proc.time()[3] - startTime, "\n")
        
        #cat("working on if !istwo\n")
        #startTime <- proc.time()[3]
        
        if (!istwo) {
            #======== test 3
            emResult <- .em3Genos(hint, nm[!rmid])
            T <- round(emResult$T, 4)
            tgeno3 <- rep(-1, nsize)
            geno3 <- rep(-1, lnrmid)
            
            # create the 3x3 mm matrix and sort by decreasing tau
            ig <- order(emResult$tau, decreasing = TRUE)
            mm <- matrix(c(3, 2, 1, 1, 3, 2, 1, 2, 3), nrow = 3, byrow = TRUE)
            mm <- mm[ig, ]
            
            out1 <- apply(T, 2, max)
            out <- rep(1, 3)
            out[mm[1, 3]] <- median(T[T[, mm[1, 1]] < 0.5 & T[, mm[1, 2]] < 0.5, mm[1, 3]])
            tt <- table(T[geno3 == -1, mm[2, 3]])
            stt <- sort(tt, decreasing = TRUE)[1]
            th <- sort(as.numeric(names(tt[tt == stt])), decreasing = TRUE)[1]
            out[mm[2, 3]] <- max(median(T[T[, mm[2, 1]] <= min(out[mm[2, 1]], 0.5) & T[, mm[2, 2]] <= min(out[mm[2, 2]], 0.5), mm[2, 3]]), th)
            tt <- table(T[geno3 == -1, mm[3, 3]])
            stt <- sort(tt, decreasing = TRUE)[1]
            th <- sort(as.numeric(names(tt[tt == stt])), decreasing = TRUE)[1]
            
            # out contains the threshold in this section which is used later
            out[mm[3, 3]] <- max(median(T[T[, mm[3, 1]] <= min(out[mm[3, 1]], 0.5) & T[, mm[3, 2]] <= min(out[mm[3, 2]], 0.5), mm[3, 3]]), th)
            if (any(is.na(out))) {
                if(doLog) {
                    logfn("failed to calculate thresholds for three genotype case. Falling back on two genotype test.")
                }
                # we need to fall back on the 2 vs 1 group test
                if (!isone) 
                  geno <- .test12(tscore2, nm, tgeno2, rmid, thresh, iig, nsize, logfn)
                v1 <- vinotype(nm, ns, geno, logfn)
                vino <- v1$vino
                conf <- v1$conf
            } else {
                out[out1 < out] <- out1[out1 < out]
                geno3[T[, mm[1, 3]] >= out[mm[1, 3]]] <- mm[1, 3]
                geno3[T[, mm[2, 3]] >= out[mm[2, 3]]] <- mm[2, 3]
                geno3[T[, mm[3, 3]] >= out[mm[3, 3]]] <- mm[3, 3]
                tgeno3[!rmid] <- geno3
                if (length(unique(tgeno3[tgeno3 != -1])) < 3) {
                  if(doLog) {
                      logfn(
                          "three genotype test resulted in %i groups. Falling back on two genotype test.",
                          length(unique(tgeno3[tgeno3 != -1])))
                  }
                  
                  # we need to fall back on the 2 vs 1 group test
                  if (!isone) 
                    geno <- .test12(tscore2, nm, tgeno2, rmid, thresh, iig, nsize, logfn)
                  v1 <- vinotype(nm, ns, geno, logfn)
                  vino <- v1$vino
                  conf <- v1$conf
                } else {
                  # at this point the 3 group scenario is still possible
                  noCalls <- tgeno3 == -1
                  if (any(noCalls)) {
                    # use vdist to assign membership where prev geno test did
                    # not succeed
                    tgeno3 <- .vdist(adata[, 1], adata[, 2]/5, tgeno3)
                    if(doLog) {
                        logfn("in three genotype test used vdist function to assign missing genotypes as follows:")
                        for(i in which(noCalls)) {
                            logfn("    %s: %i", sampleNames[i], tgeno3[i])
                        }
                    }
                  }
                  
                  tscore3 <- silhouette(match(tgeno3[!rmid], unique(tgeno3[!rmid])), dist(nm[!rmid]))
                  if (isone) {
                    geno <- .test13(tscore3, nm, tgeno3, rmid, geno, logfn)
                    v1 <- vinotype(nm, ns, geno, logfn)
                    vino <- v1$vino
                    conf <- v1$conf
                  } else {
                    geno <- .test123(tscore2, tscore3, nm, tgeno2, tgeno3, rmid, thresh, iig, nsize, logfn)
                    v1 <- vinotype(nm, ns, geno, logfn)
                    vino <- v1$vino
                    conf <- v1$conf
                  }
                }
            }
        } # end of if(!istwo)
        #cat(proc.time()[3] - startTime, "\n")
        #cat("##############################\n")
    }
    
    list(geno = geno, vino = vino, conf = conf)
}

# Run the EM algorithm for 3 genotypes
.em3Genos.using_r <- function(hint, nmSubset) {
    otheta1 <- list(
        tau = c(1/3, 1/3, 1/3),
        mu1 = hint[1],
        mu2 = hint[2],
        mu3 = hint[3],
        sigma1 = 0.1,
        sigma2 = 0.1,
        sigma3 = 0.1)
    theta1 <- otheta1
    
    ok <- TRUE
    delta <- 0.001
    imax <- 50
    iter <- 0
    while (ok & iter <= imax) {
        iter <- iter + 1
        
        # T is a matrix of # samples x 3 groups
        T <- .E.step3(theta1, nmSubset)
        T[is.na(T)] <- 1/3
        theta1 <- .M.step3(T, nmSubset)
        ok1 <- TRUE
        
        # determines the stopping condition of EM algo (analogous to
        # the two group version)
        ok <-
            ((theta1$tau[1] > 0 && abs(theta1$mu1[1] - otheta1$mu1[1]) >= delta) ||
             (theta1$tau[2] > 0 && abs(theta1$mu2[1] - otheta1$mu2[1]) >= delta) ||
             (theta1$tau[3] > 0 && abs(theta1$mu3[1] - otheta1$mu3[1]) >= delta)) &&
            (!is.na(theta1$sigma1) && !is.na(theta1$sigma2) &&
             !is.na(theta1$sigma3) && !is.infinite(theta1$sigma1) &&
             !is.infinite(theta1$sigma2) && !is.infinite(theta1$sigma3))
        if (ok) {
            m <- (theta1$sigma1 + theta1$sigma2 + theta1$sigma3)/3
            theta1$sigma1 <- 0.5 * theta1$sigma1 + 0.5 * m
            theta1$sigma2 <- 0.5 * theta1$sigma2 + 0.5 * m
            theta1$sigma3 <- 0.5 * theta1$sigma3 + 0.5 * m
        }
        otheta1 <- theta1
    }
    
    # TODO rename T so it doesn't overlap with the TRUE constant
    list(T = T, tau = theta1$tau)
}

.em3Genos.using_c <- function(hint, nmSubset) {
    sample_count <- as.integer(length(nmSubset))
    geno_count <- as.integer(3)
    
    c_call <- .C(
        name = .run_em_from_r,
        init_sigma = as.double(0.1),
        mus = as.double(hint),
        expectation_matrix = matrix(0.0, nrow = sample_count, ncol = geno_count),
        data_vec = as.double(nmSubset),
        taus = rep(as.double(1/3), 3),
        sample_count = sample_count,
        geno_count = geno_count)
    
    list(T = c_call$expectation_matrix, tau = c_call$taus)
}

.em3Genos <- .em3Genos.using_c

.em2Genos.using_r <- function(hint, nmSubset) {
    # Start with priors
    theta1 <- list(
        tau = c(0.5, 0.5),
        mu1 = hint[1],
        mu2 = hint[2],
        sigma1 = 0.01,
        sigma2 = 0.01)
    otheta1 <- theta1
    ok <- TRUE
    delta <- 0.001
    imax <- 50
    iter <- 0
    
    #cat(proc.time()[3] - startTime, "\n")
    #cat("iterating\n")
    #startTime <- proc.time()[3]
    
    while (ok & iter <= imax) {
        iter <- iter + 1
        
        # probability that belongs to group 1 vs prob group 2
        # T matrix is # samples x 2 groups
        T <- .E.step2(theta1, nmSubset)
        T[is.na(T)] <- 0.5
        theta1 <- .M.step2(T, nmSubset)
        ok1 <- TRUE
        
        # Determines the stopping condition of EM algo.
        # There are two groups so if 1st group mean is stable but the 2nd is
        # not we will keep iterating until both means are stable
        # 
        # tau is the overall probability of how many are in group1 vs group 2
        # the mean will be na if tau_1 <=0 or tau2 <=0
        ok <-
            ((theta1$tau[1] > 0 && abs(theta1$mu1[1] - otheta1$mu1[1]) >= delta) ||
             (theta1$tau[2] > 0 && abs(theta1$mu2[1] - otheta1$mu2[1]) >= delta)) &&
            (!is.na(theta1$sigma1) && !is.na(theta1$sigma2) &&
             !is.infinite(theta1$sigma1) && !is.infinite(theta1$sigma2))
        if (ok) {
            m <- (theta1$sigma1 + theta1$sigma2)/2
            theta1$sigma1 <- 0.5 * theta1$sigma1 + 0.5 * m
            theta1$sigma2 <- 0.5 * theta1$sigma2 + 0.5 * m
        }
        otheta1 <- theta1
    }
    
    list(T = T, tau = theta1$tau)
}

.em2Genos.using_c <- function(hint, nmSubset) {
    sample_count <- as.integer(length(nmSubset))
    geno_count <- as.integer(2)
    
    c_call <- .C(
        name = .run_em_from_r,
        init_sigma = as.double(0.01),
        mus = as.double(hint),
        expectation_matrix = matrix(0.0, nrow = sample_count, ncol = geno_count),
        data_vec = as.double(nmSubset),
        taus = rep(as.double(1/2), 2),
        sample_count = sample_count,
        geno_count = geno_count)
    
    list(T = c_call$expectation_matrix, tau = c_call$taus)
}

.em2Genos <- .em2Genos.using_c

# genotyping for probesets that we know are homozygous a priori
genotypeHomozygous <- function(nm, ns, trans, logfn=NULL) {
    onError <- function(e) {
        if(!is.null(logfn)) {
            logfn("caught an error in \"genotypeHomozygous\" function. setting all genotypes to -1")
        }
        nsize <- length(nm)
        list(geno = rep(-1, nsize), vino = rep(0, nsize), conf = rep(0, nsize))
    }
    tryCatch(.genotypeHomozygous(nm, ns, trans, logfn), error = onError)
}

.genotypeHomozygous <- function(nm, ns, trans, logfn=NULL) {
    doLog <- !is.null(logfn)
    
    nsize <- length(nm)
    sampleNames <- names(nm)
    hint <- c(max(nm), min(nm))
    
    ccsThresh <- c(-0.4, -0.3, -0.15, 0.15, 0.3, 0.4)
    maThresh  <- c(-0.8, -0.6, -0.3, 0.3, 0.6, 0.8)
    if (is.element(trans, "MA")) {
        thresh <- maThresh
    } else if(is.element(trans, "CCS")){
        thresh <- ccsThresh
    } else {
        stop("expected transformMethod to be \"CCS\" or \"MA\"")
    }
    rmid <- nm >= thresh[2] & nm <= thresh[5] & ns < quantile(ns, 0.2)
    lnrmid <- sum(!rmid)
    
    if(doLog) {
        logfn("Performing homozygous genotyping. Intensity contrast/average values per sample:")
        for(i in seq_len(nsize)) {
            logfn("    %s: %f/%f", sampleNames[i], nm[i], ns[i])
        }
        
        if(any(rmid)) {
            logfn(paste(
                "the following samples are low-intensity and low-contrast so they",
                "will be excluded from genotype thresholding and genotype",
                "clustering:"))
            for(n in sampleNames[rmid]) {
                logfn("    %s", n)
            }
        }
    }
    
    if (all(nm[!rmid] < thresh[3])) {
        if(doLog) {
            logfn("sample contrasts fall below %f so all genotypes are being set to 3 (BB)", thresh[3])
        }
        
        geno <- rep(3, nsize)
        v1 <- vinotype(nm, ns, geno, logfn)
        vino <- v1$vino
        conf <- v1$conf
    } else if (all(nm[!rmid] > thresh[4])) {
        if(doLog) {
            logfn("sample contrasts are above %f so all genotypes are being set to 1 (AA)", thresh[4])
        }
        
        geno <- rep(1, nsize)
        v1 <- vinotype(nm, ns, geno, logfn)
        vino <- v1$vino
        conf <- v1$conf
    } else if (all(nm[!rmid] <= thresh[3] | nm[!rmid] >= thresh[4])) {
        if(doLog) {
            fmtMsg <- paste(
                "sample contrasts fall outside of the range %f to %f. Negative ",
                "contrasts are set to 3 (BB) and positive contrasts are set to 1 (AA)",
                sep="")
            logfn(fmtMsg, thresh[3], thresh[4])
        }
        
        # 1,3
        geno <- rep(1, nsize)
        geno[nm < 0] <- 3
        v1 <- vinotype(nm, ns, geno, logfn)
        vino <- v1$vino
        conf <- v1$conf
    } else {
        adata <- cbind(nm, ns/(max(ns) - min(ns)))
        #======== test 2
        emResult <- .em2Genos(hint, nm[!rmid])
        T <- round(emResult$T, 4)
        geno <- rep(-1, nsize)
        geno2 <- rep(-1, lnrmid)
        ig <- order(emResult$tau, decreasing = TRUE)
        ii <- ig[1]
        geno2[T[, ii] >= median(T[T[, ig[2]] < 0.5, ii])] <- ii
        ii <- ig[2]
        tt <- table(T[geno2 == -1, ii])
        stt <- sort(tt, decreasing = TRUE)[1]
        th <- sort(as.numeric(names(tt[tt == stt])), decreasing = TRUE)[1]
        geno2[geno2 == -1 & T[, ii] >= min(max(T[, ii]), max(median(T[T[, ig[1]] < 0.5, ii]), th))] <- ii
        geno[!rmid] <- geno2
        if (length(unique(geno[geno != -1])) == 1) {
            mm <- median(nm)
            geno <- rep(1, nsize)
            if (mm < 0) 
                geno <- rep(3, nsize)
            v1 <- vinotype(nm, ns, geno, logfn)
            vino <- v1$vino
            conf <- v1$conf
            
            if(doLog) {
                fmtMsg <- paste(
                    "the two state EM was only able to assign a single genotype group. ",
                    "The contrast average is %f so genotypes have been set to %i",
                    sep="")
                logfn(fmtMsg, mm, geno[1])
            }
        } else {
            noCalls <- geno == -1
            if (any(noCalls)) {
                geno <- .vdist(adata[, 1], adata[, 2] / 2, geno)
                if(doLog) {
                    logfn("in two genotype test used vdist function to assign missing genotypes as follows:")
                    for(i in which(noCalls)) {
                        logfn("    %s: %i", sampleNames[i], geno[i])
                    }
                }
            }
            keepthis <- tapply(nm, geno, mean)
            if (keepthis[1] > keepthis[2]) {
                geno[geno == 2] <- 3
            } else {
                geno[geno == 1] <- 3
                geno[geno == 2] <- 1
            }
            v1 <- vinotype(nm, ns, geno, logfn)
            vino <- v1$vino
            conf <- v1$conf
        }
    }
    
    list(geno = geno, vino = vino, conf = conf)
}

# test three groups (the tscore parameters are silhoutte scores)
.test123 <- function(tscore2, tscore3, nm, tgeno2, tgeno3, rmid, thresh, iig, nsize, logfn=NULL) {
    if (length(tscore3) < 3) {
        # the score is not available
        mscore3 <- 0
    } else {
        # use the mean of the 3rd column which stores avg scores
        mscore3 <- mean(tscore3[, 3])
    }
    
    if (length(tscore2) < 3) {
        # the score is not available
        mscore2 <- 0
    } else {
        # use the mean of the 3rd column which stores avg scores
        mscore2 <- mean(tscore2[, 3])
    }
    
    # calculates the difference between the 0.1 and 0.9 quantiles
    d1 <- quantile(nm[tgeno3 == 1 & !rmid], 0.1) - quantile(nm[tgeno3 == 2 & !rmid], 0.9)
    d2 <- quantile(nm[tgeno3 == 2 & !rmid], 0.1) - quantile(nm[tgeno3 == 3 & !rmid], 0.9)
    if (((mscore2 - mscore3 <= 0.15) | mscore3 > 0.8) & (d1 > 0.1 & d2 > 0.1)) {
        # three groups
        geno <- tgeno3
    } else {
        if(!is.null(logfn)) {
            msgFmt <- paste(
                "\".test123\" is falling back on \".test12\" based on ",
                "the following values: mscore2=%d, mscore3=%d, d1=%d, d2=%d",
                sep="")
            logfn(msgFmt, mscore2, mscore3, d1, d2)
        }
        geno <- .test12(tscore2, nm, tgeno2, rmid, thresh, iig, nsize, logfn)
    }
    
    geno
}

.test13 <- function(tscore3, nm, tgeno3, rmid, geno, logfn=NULL) {
    if (length(tscore3) < 3) {
        # the score is not available
        mscore3 <- 0
    } else {
        # use the mean of the 3rd column which stores avg scores
        mscore3 <- mean(tscore3[, 3])
    }
    
    # calculates the difference between the 0.1 and 0.9 quantiles
    d1 <- quantile(nm[tgeno3 == 1 & !rmid], 0.1) - quantile(nm[tgeno3 == 2 & !rmid], 0.9)
    d2 <- quantile(nm[tgeno3 == 2 & !rmid], 0.1) - quantile(nm[tgeno3 == 3 & !rmid], 0.9)
    if (mscore3 > 0.65 & (d1 > 0.1 & d2 > 0.1)) {
        geno <- tgeno3
    } else if(!is.null(logfn)) {
        msgFmt <- paste(
            "in \".test13\" we will leave the genotypes unchanged based on ",
            "the following values: mscore3=%d, d1=%d, d2=%d",
            sep="")
        logfn(msgFmt, mscore3, d1, d2)
    }
    
    geno
}

# test two groups
.test12 <- function(tscore2, nm, tgeno, rmid, thresh, iig, nsize, logfn=NULL) {
    if (length(tscore2) < 3) {
        # the score is not available
        mscore <- 0
    } else {
        # use the mean of the 3rd column which stores avg scores
        mscore <- mean(tscore2[, 3])
    }
    
    # calculates the difference between the 0.1 and 0.9 quantiles
    d <- quantile(nm[tgeno == 1 & !rmid], 0.1) - quantile(nm[tgeno == 2 & !rmid], 0.9)
    
    # two group
    if (mscore > 0.6 & d > 0.1) {
        if (length(iig) == 0) {
            # length(iig) == 0 indicates that we went with one of the obvious
            # cases in the genotype function so now we need to figure out based
            # on threshold
            tmp <- c(median(nm[tgeno == 1]), median(nm[tgeno == 2]))
            if (tmp[1] > thresh[5] & tmp[2] < thresh[2]) {
                iig <- c(1, 3)
            } else if (tmp[1] < thresh[5]) {
                iig <- c(2, 3)
            } else {
                iig <- c(1, 2)
            }
        }
        
        tgeno <- iig[match(tgeno, sort(unique(tgeno)))]
    }
    else {
        if(!is.null(logfn)) {
            msgFmt <- paste(
                "in \".test12\" we must fall back on assigning genotype based on ",
                "thresholds since either the difference between contrast quantiles ",
                "(%d) is too small or the average silhouette score (%d) is too small",
                sep="")
            logfn(msgFmt, d, mscore)
        }
        
        mm <- median(nm)
        if (mm > thresh[5]) {
            tgeno <- rep(1, nsize)
        } else if (mm < thresh[2]) {
            tgeno <- rep(3, nsize)
        } else {
            tgeno <- rep(2, nsize)
        }
    }
    
    tgeno
}

# vdist performs hierarchical clustering (our fallback function when we are
# left with unassigned genotypes)
.vdist.using_r <- function(ta, tb, t2) {
    # the list of unassigned geno indices
    la <- which(t2 == -1)
    
    # the number of unassigned genos
    l <- length(la)
    
    # dta is a symetrix matrix where each cell measures the euclidian distance
    # two rows in the matrix. For example,
    # sqrt((ta[1] - ta[3]) ^ 2 + (tb[1] - tb[3]) ^ 2) == dta[1, 3] == dta[3, 1]
    dta <- as.matrix(dist(cbind(ta, tb)))
    diag(dta) <- 1000
    while (l > 0) {
        # t3 contains all valid genotypes
        t3 <- t2[t2 != -1]
        
        # tmp is the distance matrix where the rows are from unassigned genos
        # and the the cols are from assigned genos
        tmp <- dta[la, t2 != -1]
        if (l == 1) {
            # if there is only 1 unassigned genotype assign it to the
            # nearest valid genotype
            t2[la] <- t3[which(min(tmp) == tmp)[1]]
        } else {
            # id is the index from tmp with the smallest distance
            id <- which(tmp == min(tmp))[1]
            
            # iid is the tmp row of the unassigned geno with the smallest distance
            iid <- id%%l
            iid[iid == 0] <- l
            
            # la[iid] recovers the index of the nearest unassigned geno which
            # we then assign it to the nearest genotype
            t2[la[iid]] <- t3[which(tmp[iid, ] == min(tmp[iid, ]))[1]]
        }
        
        la <- which(t2 == -1)
        l <- length(la)
    }
    t2
}

.vdist.using_c <- function(ta, tb, t2) {
    c_call <- .C(
        name = .vdist_from_r,
        vectors_length = as.integer(length(t2)),
        ta = as.double(ta),
        tb = as.double(tb),
        t2 = as.integer(t2))
    c_call$t2
}

.vdist <- .vdist.using_c

.E.step3.using_r <- function(theta, data) {
    i1 <- rep(0, length(data))
    i2 <- i1
    i3 <- i1
    if (theta$tau[1] > 0) 
        i1 <- theta$tau[1] * dnorm(data, mean = theta$mu1, sd = sqrt(theta$sigma1))
    if (theta$tau[2] > 0) 
        i2 <- theta$tau[2] * dnorm(data, mean = theta$mu2, sd = sqrt(theta$sigma2))
    if (theta$tau[3] > 0) 
        i3 <- theta$tau[3] * dnorm(data, mean = theta$mu3, sd = sqrt(theta$sigma3))
    t(apply(cbind(i1, i2, i3), 1, function(x) x/sum(x)))
}

.E.step3.using_c <- function(theta, data) {
    data_len <- length(data)
    c_call <- .C(
        name = .calc_expectation_three_genos_from_r,
        as.double(data),
        as.integer(data_len),
        as.double(theta$tau),
        as.double(theta$mu1),
        as.double(theta$mu2),
        as.double(theta$mu3),
        as.double(theta$sigma1),
        as.double(theta$sigma2),
        as.double(theta$sigma3),
        expectation_matrix = matrix(0.0, nrow = data_len, ncol = 3))
    
    c_call$expectation_matrix
}

.E.step3 <- .E.step3.using_c

.M.step3.using_r <- function(T, data) {
    mu1 <- NA
    mu2 <- NA
    mu3 <- NA
    sigma1 <- NA
    sigma2 <- NA
    sigma3 <- NA
    tau <- apply(T, 2, mean)
    if (tau[1] > 0) {
        mu1 <- weighted.mean(data, T[, 1])
        sigma1 <- cov.wt(matrix(data, ncol = 1), T[, 1])$cov
    }
    if (tau[2] > 0) {
        mu2 <- weighted.mean(data, T[, 2])
        sigma2 <- cov.wt(matrix(data, ncol = 1), T[, 2])$cov
    }
    if (tau[3] > 0) {
        mu3 <- weighted.mean(data, T[, 3])
        sigma3 <- cov.wt(matrix(data, ncol = 1), T[, 3])$cov
    }
    list(tau = tau, mu1 = mu1, mu2 = mu2, mu3 = mu3, sigma1 = sigma1, sigma2 = sigma2, sigma3 = sigma3)
}

.M.step3.using_c <- function(T, data)
{
    data_len <- length(data)
    c_call <- .C(
        name = .maximize_expectation_three_genos_from_r,
        T,
        data,
        as.integer(data_len),
        taus = c(0.0, 0.0, 0.0),
        mus = c(0.0, 0.0, 0.0),
        sigmas = c(0.0, 0.0, 0.0))
    list(
        tau = c_call$taus,
        mu1 = c_call$mus[1],
        mu2 = c_call$mus[2],
        mu3 = c_call$mus[3],
        sigma1 = c_call$sigmas[1],
        sigma2 = c_call$sigmas[2],
        sigma3 = c_call$sigmas[3])
}

.M.step3 <- .M.step3.using_c

.E.step2.using_r <- function(theta, data) {
    i1 <- rep(0, length(data))
    i2 <- i1
    if (theta$tau[1] > 0) 
        i1 <- theta$tau[1] * dnorm(data, mean = theta$mu1, sd = sqrt(theta$sigma1))
    if (theta$tau[2] > 0) 
        i2 <- theta$tau[2] * dnorm(data, mean = theta$mu2, sd = sqrt(theta$sigma2))
    t(apply(cbind(i1, i2), 1, function(x) x/sum(x)))
}

.E.step2.using_c <- function(theta, data) {
    data_len <- length(data)
    c_call <- .C(
        name = .calc_expectation_two_genos_from_r,
        as.double(data),
        as.integer(data_len),
        as.double(theta$tau),
        as.double(theta$mu1),
        as.double(theta$mu2),
        as.double(theta$sigma1),
        as.double(theta$sigma2),
        expectation_matrix = matrix(0.0, nrow = data_len, ncol = 2))
    
    c_call$expectation_matrix
}

.E.step2 <- .E.step2.using_c

.M.step2.using_c <- function(T, data)
{
    data_len <- length(data)
    c_call <- .C(
        name = .maximize_expectation_two_genos_from_r,
        T,
        data,
        as.integer(data_len),
        taus = c(0.0, 0.0),
        mus = c(0.0, 0.0),
        sigmas = c(0.0, 0.0))
    list(
        tau = c_call$taus,
        mu1 = c_call$mus[1],
        mu2 = c_call$mus[2],
        sigma1 = c_call$sigmas[1],
        sigma2 = c_call$sigmas[2])
}

.M.step2.using_r <- function(T, data) {
    mu1 <- NA
    mu2 <- NA
    sigma1 <- NA
    sigma2 <- NA
    tau <- apply(T, 2, mean)
    if (tau[1] > 0) {
        mu1 <- weighted.mean(data, T[, 1])
        sigma1 <- cov.wt(matrix(data, ncol = 1), T[, 1])$cov
    }
    if (tau[2] > 0) {
        mu2 <- weighted.mean(data, T[, 2])
        sigma2 <- cov.wt(matrix(data, ncol = 1), T[, 2])$cov
    }
    list(tau = tau, mu1 = mu1, mu2 = mu2, sigma1 = sigma1, sigma2 = sigma2)
}

.M.step2 <- .M.step2.using_c
