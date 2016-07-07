import math

#output frequency
a = [161,168,167,92,123]
f = 50 #input freq


print a

for i in a:
    m = 1000/f
    d = 0
    while True:
        new_d = math.floor(4*f*m/i)/4
        new_m = math.ceil(4*new_d*i/f)/4
        if new_m ==m and new_d==d:
            break
        m = new_m
        d = new_d
    print "FINAL:i,m,d=%d,%f,%f" % (i,m,d)
